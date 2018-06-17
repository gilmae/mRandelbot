FROM andrius/alpine-ruby:latest

RUN apk add --no-cache  go
RUN apk add --no-cache		bash 
RUN apk add --no-cache      exiftool
RUN apk add --no-cache      coreutils
RUN apk add --no-cache sqlite
RUN apk --no-cache add git
RUN apk add --update ruby-dev build-base \
  libxml2-dev libxslt-dev pcre-dev libffi-dev \
  sqlite-dev
RUN apk add --no-cache imagemagick

WORKDIR /

RUN gem install bundler --no-ri --no-rdoc

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN go get github.com/gilmae/mandelbrot/...

RUN mkdir mRandelbot
ADD *.rb mRandelbot/
ADD Gemfile mRandelbot
WORKDIR mRandelbot
RUN bundle install

WORKDIR /