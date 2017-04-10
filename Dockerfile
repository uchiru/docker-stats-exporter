FROM docker

RUN apk --no-cache add ruby ruby-dev ruby-irb ruby-rdoc
RUN gem install rack

RUN mkdir -p /app
COPY config.ru /app/
WORKDIR /app

EXPOSE 9292

CMD ["rackup", "-o", "0.0.0.0"]
