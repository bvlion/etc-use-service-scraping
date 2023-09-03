FROM ruby:3.1

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add 
RUN echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | tee  /etc/apt/sources.list.d/google-chrome.list
RUN apt-get update -qq
RUN apt-get install -y google-chrome-stable libnss3 libgconf-2-4

RUN CHROMEDRIVER_VERSION=`curl -sS https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_STABLE` \
 && curl -sS -o /tmp/chromedriver_linux64.zip https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/$CHROMEDRIVER_VERSION/linux64/chromedriver-linux64.zip
RUN unzip /tmp/chromedriver_linux64.zip
RUN mv chromedriver /usr/local/bin/

RUN gem install bundler

WORKDIR /app
COPY . /app

RUN bundle install

CMD ["ruby", "scraper.rb"]