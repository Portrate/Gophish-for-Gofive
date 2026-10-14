# Minify client side assets (JavaScript)
FROM node:16 AS build-js

RUN npm install gulp gulp-cli -g

WORKDIR /build
COPY . .
RUN npm install --only=dev
RUN gulp


# Build Golang binary
FROM golang:1.15.2 AS build-golang

WORKDIR /go/src/github.com/gophish/gophish
COPY . .
RUN go get -v && go build -v


# Runtime container
FROM debian:stable-slim

RUN useradd -m -d /opt/gophish -s /bin/bash app

RUN apt-get update && \
	apt-get install --no-install-recommends -y jq libcap2-bin ca-certificates curl && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt/gophish
COPY --from=build-golang /go/src/github.com/gophish/gophish/ ./
COPY --from=build-js /build/static/js/dist/ ./static/js/dist/
COPY --from=build-js /build/static/css/dist/ ./static/css/dist/
COPY --from=build-golang /go/src/github.com/gophish/gophish/config.json ./
RUN chown app. config.json

RUN setcap 'cap_net_bind_service=+ep' /opt/gophish/gophish

# Persistent data dir for the SQLite DB, owned by the app user so a
# mounted volume + DB_FILE_PATH=/opt/gophish/data/gophish.db is writable
RUN mkdir -p /opt/gophish/data && chown app. /opt/gophish/data

USER app
RUN sed -i 's/127.0.0.1/0.0.0.0/g' config.json
RUN touch config.json.tmp

EXPOSE 3333 8080 8443 80

# Probe the admin server. Tries HTTPS first (the default, with a self-signed
# cert hence -k), falling back to HTTP in case ADMIN_USE_TLS was overridden.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
	CMD curl -skf https://localhost:3333/ || curl -sf http://localhost:3333/ || exit 1

CMD ["bash", "./docker/run.sh"]
