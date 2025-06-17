FROM ruby:3.2.2

WORKDIR /app

ADD .ruby-version .ruby-gemset Gemfile Gemfile.lock /app
RUN bundle install

ADD server.rb /app

ENTRYPOINT ["bundle"]
CMD ["exec", "server.rb"]

EXPOSE 4777
