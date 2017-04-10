FROM docker

RUN apk --no-cache add ruby

RUN mkdir -p /app
COPY config.ru /app/
WORKDIR /app
