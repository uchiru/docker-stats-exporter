FROM docker:17.03.1-ce

RUN apk --no-cache add ruby ruby-dev ruby-irb ruby-rdoc ruby-io-console build-base
RUN gem install bundler

ENV APP_ENV production
RUN mkdir -p /app
WORKDIR /app

COPY Gemfile /app
COPY Gemfile.lock /app
RUN bundle install

COPY . /app

EXPOSE 3120

CMD ["rackup"]
