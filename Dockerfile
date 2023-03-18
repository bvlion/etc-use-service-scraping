FROM ruby:3.1-alpine

RUN gem install bundler

WORKDIR /app
COPY . /app

RUN bundle install

CMD ["ruby", "scraper.rb"]
# CMD /bin/sh -c "while sleep 1000; do :; done"