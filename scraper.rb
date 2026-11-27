require 'selenium-webdriver'
require 'digest'
require 'csv'
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'tmpdir'

class Scraper
  attr_reader :driver
  attr_reader :options

  def initialize
    @options = Selenium::WebDriver::Chrome::Options.new.tap do |option|
      option.add_argument('--window-size=500,1200')
      option.add_argument('--headless')
      option.add_argument("--no-sandbox")
    end
  end

  def scrape
    is_pull_request = ENV.fetch('GITHUB_EVENT_NAME', '') == 'pull_request'
    pull_request_number = ENV.fetch('GITHUB_REF', '').match(/refs\/pull\/(\d+)\//)&.captures&.first || 'unknown'
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    source_path = File.expand_path(__FILE__)
    download_link_xpath = '/html/body/center/div[2]/ul/li[6]/a'
    screen_state_script = <<~JAVASCRIPT
      return {
        service_page: location.hostname === 'www2.etc-meisai.jp',
        document_ready: document.readyState === 'complete',
        login_form: document.querySelector('[name="risLoginId"], [name="risPassword"]') !== null,
        login_ready: document.querySelector('[name="risLoginId"]') !== null &&
          document.querySelector('[name="risPassword"]') !== null &&
          document.querySelector('[name="focusTarget"]') !== null && typeof submitPage === 'function',
        navigation_function: typeof submitOpenPage === 'function',
        download_link: document.evaluate(arguments[0], document, null,
          XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue !== null
      };
    JAVASCRIPT

    begin
      stage, stage_line = 'browser_start', __LINE__
      puts "stage=#{stage} ruby=#{RUBY_VERSION} selenium=#{Selenium::WebDriver::VERSION}"
      FileUtils.mkdir_p('/app/downloads')
      download_directory = Dir.mktmpdir('etc-', '/app/downloads')
      # M1 の Chromium は共有ディレクトリに別のユーザーで書き込む。
      File.chmod(0o733, download_directory) if ENV.fetch('M1_LOCAL', 'false') == 'true'
      options.add_preference(:download, {
        'prompt_for_download' => false,
        'default_directory' => download_directory,
        'directory_upgrade' => true
      })
      sleep 5
      setup_driver()
      capabilities = driver.capabilities
      chrome_version = capabilities.browser_version.to_s[/\A\d+(?:\.\d+)+/] || 'unavailable'
      chrome_driver_version = capabilities['chrome']&.fetch('chromedriverVersion', nil).to_s[/\A\d+(?:\.\d+)+/] || 'unavailable'
      puts "chrome=#{chrome_version} chromedriver=#{chrome_driver_version}"

      wait = Selenium::WebDriver::Wait.new(timeout: 30)
      stage, stage_line = 'login_page', __LINE__
      puts "stage=#{stage}"
      login_page_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      driver.get('https://www2.etc-meisai.jp/etc/R?funccode=1013000000&nextfunc=1013000000')
      wait.until do
        screen_state = driver.execute_script(screen_state_script, download_link_xpath)
        screen_state.fetch('service_page') && screen_state.fetch('login_ready')
      end
      login_page_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - login_page_started_at
      puts "login_page=ready elapsed_seconds=#{login_page_elapsed.round(2)}"

      stage, stage_line = 'login', __LINE__
      puts "stage=#{stage}"
      driver.find_element(:name, "risLoginId").send_keys ENV.fetch("USER_ID")
      driver.find_element(:name, "risPassword").send_keys ENV.fetch("PASSWORD")
      driver.find_element(:name, "focusTarget").click

      wait.until do
        screen_state = driver.execute_script(screen_state_script, download_link_xpath)
        screen_state.fetch('navigation_function') && !screen_state.fetch('login_form')
      end

      stage, stage_line = 'navigation', __LINE__
      puts "stage=#{stage}"
      driver.execute_script("submitOpenPage('frm', '/etc/R?funccode=1013000000&nextfunc=1013500000', 'self')")
      wait.until do
        screen_state = driver.execute_script(screen_state_script, download_link_xpath)
        screen_state.fetch('download_link') && !screen_state.fetch('login_form')
      end
      download_link = driver.find_element(:xpath, download_link_xpath)

      stage, stage_line = 'csv_download', __LINE__
      puts "stage=#{stage}"
      has_download_started = false
      download_link.click
      screen_state = driver.execute_script(screen_state_script, download_link_xpath)
      downloaded_files = wait.until do
        has_download_started ||= !Dir.empty?(download_directory)
        files = Dir.glob('*.csv', base: download_directory)
        files unless files.empty?
      end
      
      stage, stage_line = 'csv_read', __LINE__
      csv_rows = []
      downloaded_files.each do |file_name|
        CSV.open(File.join(download_directory, file_name), encoding: 'Shift_JIS') do |csv|
          header = csv.shift
          raise CSV::MalformedCSVError.new('Invalid ETC CSV header', 1) unless header && header.length >= 9

          csv.each { |row| csv_rows.push(row) }
        end
      end
      csv_rows.reverse!

      stage, stage_line = 'difference', __LINE__
      before_hash = ''
      save_text_file_name = 'before_hash.txt'
      File.open(save_text_file_name, 'r') do |file|
        before_hash = file.read.strip
      end

      text = ''
      latest_digest = nil
      csv_rows.each_with_index do |row, i|

        latest_text = '入: '
        if row[0] != nil && row[1] != nil
          latest_text << row[0] + ' ' + row[1]
        end
        if row[4] != nil
          latest_text << ' = ' + row[4].encode("UTF-8")
        end
        latest_text << "\n"

        latest_text << '出: ' + row[2] + ' ' + row[3]
        if row[5] != nil
          latest_text << ' = ' + row[5].encode("UTF-8")
        end
        latest_text << "\n"

        latest_text << '暫定金額: '
        if row[8] != nil
          latest_text << row[8].to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,') + ' 円'
        end
        latest_text << "\n"

        digest = Digest::SHA256.hexdigest(latest_text)

        if before_hash == digest
          break
        end
        
        latest_digest = digest if i == 0
        text << "\n\n" if i > 0
        text << "新しい ETC の利用が確認されました！\n\n" if i == 0
        text << latest_text
      end

      puts "csv=success has_new_details=#{!text.empty?}"

      stage, stage_line = 'slack_notification', __LINE__
      if is_pull_request
        puts "stage=#{stage}"
        slack_post({
          channel: ENV.fetch('ERROR_CHANNEL'),
          text: "##{pull_request_number} の PR がマージできます",
          icon_url: ENV.fetch('SUCCESS_ICON_URL')
        })
      elsif !text.empty?
        puts "stage=#{stage}"
        slack_post({
          channel: ENV.fetch('SUCCESS_CHANNEL'),
          text: text,
          icon_url: ENV.fetch('SUCCESS_ICON_URL')
        })
      end

      stage, stage_line = 'save_difference', __LINE__
      File.write(save_text_file_name, "#{latest_digest}\n") if latest_digest
    rescue => error
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      line_number = error.backtrace_locations&.find do |location|
        File.expand_path(location.path.to_s) == source_path && location.lineno.to_i.positive?
      end&.lineno || stage_line
      failure = "stage=#{stage} exception=#{error.class} source=scraper.rb:#{line_number} elapsed_seconds=#{elapsed.round(2)}"
      warn failure
      warn "last_screen=#{screen_state.to_json}" if screen_state
      warn "download_started=#{has_download_started}" if stage == 'csv_download'

      begin
        stage, stage_line = 'slack_error_notification', __LINE__
        puts "stage=#{stage}"
        text = if is_pull_request
                 "##{pull_request_number} の PR はマージできません"
               else
                 '取得できなかったためエラーメッセージの確認をお願いいたします(´･ω･`)'
               end
        slack_post({
          channel: ENV.fetch('ERROR_CHANNEL'),
          text: "#{text}\n\n#{failure}",
          icon_url: ENV.fetch('ERROR_ICON_URL')
        })
      rescue => notification_error
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        line_number = notification_error.backtrace_locations&.find do |location|
          File.expand_path(location.path.to_s) == source_path && location.lineno.to_i.positive?
        end&.lineno || stage_line
        warn "stage=#{stage} exception=#{notification_error.class} source=scraper.rb:#{line_number} elapsed_seconds=#{elapsed.round(2)}"
      end
      exit 1
    ensure
      begin
        driver&.quit
      rescue => cleanup_error
        warn "stage=browser_shutdown exception=#{cleanup_error.class}"
      end
      begin
        FileUtils.remove_entry_secure(download_directory) if download_directory
      rescue => cleanup_error
        warn "stage=remove_download exception=#{cleanup_error.class}"
      end
    end
  end

  def slack_post(data)
    data.store('username', 'ETC 利用明細 scraper')
    request_url = ENV.fetch('SLACK_WEBHOOK_URL')
    uri = URI.parse(request_url)
    response = Net::HTTP.post_form(uri, {"payload" => data.to_json})
    return if response.code == '200' && response.body.to_s.strip == 'ok'

    warn "slack_http_status=#{response.code}"
    raise IOError, 'Slack webhook did not acknowledge delivery'
  end

  def setup_driver
    if ENV.fetch('M1_LOCAL') {'false'} == 'true'
      @driver = Selenium::WebDriver.for(:remote, options: options, url: "http://#{ENV.fetch('SELENIUM_HOST')}/wd/hub")
    else
      options.page_load_strategy = :eager
      @driver = Selenium::WebDriver.for(:chrome, options: options)
      driver.manage.timeouts.page_load = 30
    end
    driver.manage.timeouts.implicit_wait = 10
    sleep 1
  end
end

$stdout.sync = true
Scraper.new.scrape
