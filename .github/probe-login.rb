require 'selenium-webdriver'
require 'json'
require 'uri'

login_url = 'https://www2.etc-meisai.jp/etc/R?funccode=1013000000&nextfunc=1013000000'
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--headless')
options.add_argument('--no-sandbox')
options.add_argument('--window-size=500,1200')
options.page_load_strategy = :none
options.add_option('goog:loggingPrefs', {performance: 'ALL'})
$stdout.sync = true
puts "ruby=#{RUBY_VERSION} selenium=#{Selenium::WebDriver::VERSION} net_http_read_timeout=#{Net::HTTP.new('localhost').read_timeout}"
system('df', '-h', '/dev/shm')
driver = Selenium::WebDriver.for(:chrome, options: options)
puts "chrome=#{driver.capabilities.browser_version}"
driver.get(login_url)
known_hosts = %w[www2.etc-meisai.jp www.etc-plaza.jp code.jquery.com]
known_errors = %w[net::ERR_CONNECTION_TIMED_OUT net::ERR_TIMED_OUT net::ERR_CONNECTION_RESET net::ERR_NAME_NOT_RESOLVED net::ERR_SSL_PROTOCOL_ERROR net::ERR_ABORTED net::ERR_INTERNET_DISCONNECTED net::ERR_HTTP2_PROTOCOL_ERROR]
requests = {}
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
last_state = nil
loop do
  state = driver.execute_script(<<~JS)
    return {
      ready: document.readyState,
      sourceHost: location.hostname === 'www2.etc-meisai.jp',
      loginForm: !!document.querySelector('[name="risLoginId"]') && !!document.querySelector('[name="risPassword"]')
    };
  JS
  if state != last_state
    puts "elapsed=#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(2)} browser_state=#{state.to_json}"
    last_state = state
  end
  driver.logs.get(:performance).each do |entry|
    message = JSON.parse(entry.message).fetch('message')
    fields = message.fetch('params')
    id = fields['requestId']
    case message.fetch('method')
    when 'Network.requestWillBeSent'
      address = URI.parse(fields.fetch('request').fetch('url'))
      next unless known_hosts.include?(address.host)
      resource = address.host == 'www2.etc-meisai.jp' ? fields['type'] : address.path
      requests[id] = [address.host, resource]
      puts "request host=#{address.host} resource=#{resource}" if resource == 'Document' || address.host != known_hosts.first
    when 'Network.responseReceived'
      host, resource = requests[id]
      next unless host && (resource == 'Document' || host != known_hosts.first)
      puts "response host=#{host} resource=#{resource} status=#{fields.fetch('response').fetch('status')}"
    when 'Network.loadingFailed'
      host, resource = requests[id]
      next unless host
      reason = fields['errorText']
      puts "failure host=#{host} resource=#{resource} reason=#{known_errors.include?(reason) ? reason : 'other'}"
    end
  end
  break if state['loginForm'] && state['ready'] == 'complete'
  break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at >= 33
  sleep 1
end
driver.quit
