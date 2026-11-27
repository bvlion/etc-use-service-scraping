FROM ruby:3.3-bookworm

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add 
RUN echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | tee /etc/apt/sources.list.d/google-chrome.list
RUN apt-get update -qq
RUN apt-get install -y google-chrome-stable libnss3 libgconf-2-4
RUN CHROME_MAJOR_VERSION=$(google-chrome --version | grep -oE "[0-9]+" | head -1) && \
    CHROMEDRIVER_VERSION=`curl -sS https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_$CHROME_MAJOR_VERSION` && \
    curl -sS -o /tmp/chromedriver_linux64.zip https://storage.googleapis.com/chrome-for-testing-public/$CHROMEDRIVER_VERSION/linux64/chromedriver-linux64.zip
RUN unzip /tmp/chromedriver_linux64.zip
RUN mv chromedriver-linux64/chromedriver /usr/local/bin/
RUN rm -rf chromedriver-linux64 && google-chrome --version && chromedriver --version

WORKDIR /app
COPY Gemfile Gemfile.lock ./

ENV BUNDLE_FROZEN=true
RUN gem install bundler --version "$(tail -n 1 Gemfile.lock | tr -d '[:space:]')" --no-document
RUN bundle install

COPY scraper.rb before_hash.txt ./
CMD ["bundle", "exec", "ruby", "scraper.rb"]
