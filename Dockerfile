FROM harbor.k8s.libraries.psu.edu/library/ruby-3.1.2-node-16:20231030 as base
ARG UID=2000

COPY bin/vaultshell /usr/local/bin/
USER root
RUN apt-get update && \
   apt-get install --no-install-recommends -y \
   shared-mime-info \
   imagemagick=8:6.9.10.23+dfsg-2.1+deb10u5 \
   ghostscript\
   libreoffice && \
   rm -rf /var/lib/apt/lists*

COPY config/policy.xml /etc/ImageMagick-6/policy.xml
RUN useradd -u $UID app -d /app
RUN mkdir /app/tmp
RUN chown -R app /app
USER app


COPY Gemfile Gemfile.lock /app/
# in the event that bundler runs outside of docker, we get in sync with it's bundler version
RUN gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)"
RUN bundle config set path 'vendor/bundle'
RUN bundle install && \
  rm -rf /app/.bundle/cache && \
  rm -rf /app/vendor/bundle/ruby/*/cache


COPY package.json yarn.lock /app/
RUN yarn --frozen-lockfile && \
  rm -rf /app/.cache && \
  rm -rf /app/tmp


COPY --chown=app . /app

CMD ["/app/bin/startup"]

FROM base as dev

USER root
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list

RUN apt-get update && apt-get install -y x11vnc \
    xvfb \
    fluxbox \
    wget \
    sqlite3 \
    rsync \
    libsqlite3-dev \
    libnss3 \
    wmctrl \
    google-chrome-stable

USER app
RUN bundle config set path 'vendor/bundle'

# Final Target
FROM base as production

# Clean up Bundle
RUN bundle install --without development test && \
  bundle clean && \
  rm -rf /app/.bundle/cache && \
  rm -rf /app/vendor/bundle/ruby/*/cache

RUN RAILS_ENV=production \
  NODE_ENV=production \
  DEFAULT_URL_HOST=localhost \
  SECRET_KEY_BASE=rails_bogus_key \
  AWS_BUCKET=bucket \
  AWS_ACCESS_KEY_ID=key \
  AWS_SECRET_ACCESS_KEY=secret \
  AWS_REGION=us-east-1 \
  bundle exec rails assets:precompile && \
  rm -rf /app/.cache/ && \
  rm -rf /app/node_modules/.cache/ && \
  rm -rf /app/tmp/

CMD ["/app/bin/startup"]
