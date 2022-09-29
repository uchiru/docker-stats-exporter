FROM ruby:2.7.6

ENV APP_ENV production
RUN mkdir -p /app
WORKDIR /app

COPY Gemfile /app
COPY Gemfile.lock /app
RUN bundle install

COPY . /app

EXPOSE 3120

CMD ["rackup"]
