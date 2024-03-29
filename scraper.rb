require 'selenium-webdriver'
require 'digest'
require 'csv'
require 'net/http'
require 'uri'
require 'json'

class Scraper
  attr_reader :driver
  attr_reader :options

  def initialize
    sleep 5
    @options = Selenium::WebDriver::Chrome::Options.new.tap do |option|
      option.add_argument('--window-size=500,1200')
      option.add_argument('--headless')
      option.add_argument("--no-sandbox")
      option.add_preference(:download, {
        'prompt_for_download'=> false,
        'default_directory' => '/app/downloads',
        'directory_upgrade' => true
      })
    end
  end

  def scrape
    begin
      setup_driver()
      puts 'start scraping'
      
      driver.get('https://www2.etc-meisai.jp/etc/R?funccode=1013000000&nextfunc=1013000000')
      driver.find_element(:name, "risLoginId").send_keys ENV.fetch("USER_ID")
      driver.find_element(:name, "risPassword").send_keys ENV.fetch("PASSWORD")
      driver.find_element(:name, "focusTarget").click
      sleep 1

      driver.execute_script("submitOpenPage('frm', '/etc/R?funccode=1013000000&nextfunc=1013500000', 'self')")
      sleep 2

      driver.find_element(:xpath, '/html/body/center/div[2]/ul/li[6]/a').click()
      sleep 1

      driver.close()

      puts 'end scraping'
      
      csv_rows = []
      Dir.glob("/app/downloads/*.csv") do |file_path|
        CSV.foreach(file_path, encoding: 'Shift_JIS').with_index(0) do |row, i|
          next if i < 1
          csv_rows.push(row)
        end
      end
      csv_rows.reverse!

      puts "csv_rows is empty" if csv_rows.empty?

      before_hash = ''
      save_text_file_name = 'before_hash.txt'
      File.open(save_text_file_name, 'r') do |file|
        before_hash = file.read.strip
      end

      text = ''
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
        
        if i == 0
          File.open(save_text_file_name, 'w') do |file| 
            file.puts(digest)
          end            
        end

        text << "\n\n" if i > 0
        text << "新しい ETC の利用が確認されました！\n\n" if i == 0
        text << latest_text
      end

      puts "text.length is #{text.length}"

      slacl_post({
        channel: ENV.fetch('SUCCESS_CHANNEL'),
        text: text,
        icon_url: ENV.fetch('SUCCESS_ICON_URL')
      }) if text != ''
    rescue => e
      slacl_post({
        channel: ENV.fetch('ERROR_CHANNEL'),
        text: "取得できなかったためエラーメッセージの確認をお願いいたします(´･ω･`)\n\n#{e.message}",
        icon_url: ENV.fetch('ERROR_ICON_URL')
      })
    end
  end

  def slacl_post(data)
    data.store('username', 'ETC 利用明細 scraper')
    request_url = ENV.fetch('SLACK_WEBHOOK_URL')
    uri = URI.parse(request_url)
    Net::HTTP.post_form(uri, {"payload" => data.to_json})  
  end

  def setup_driver
    if ENV.fetch('M1_LOCAL') {'false'} == 'true'
      @driver = Selenium::WebDriver.for(:remote, options: options, url: "http://#{ENV.fetch('SELENIUM_HOST')}/wd/hub")
    else
      @driver = Selenium::WebDriver.for(:chrome, options: options)
    end
    driver.manage.timeouts.implicit_wait = 10
    sleep 1
  end
end

Scraper.new.scrape
