FROM ruby:3.3-bookworm

WORKDIR /app
COPY Gemfile Gemfile.lock ./

ENV BUNDLE_FROZEN=true
RUN gem install bundler --version "$(tail -n 1 Gemfile.lock | tr -d '[:space:]')" --no-document
RUN bundle install

COPY scraper.rb before_hash.txt ./
CMD ["bundle", "exec", "ruby", "scraper.rb"]
# CMD /bin/sh -c "while sleep 1000; do :; done"
