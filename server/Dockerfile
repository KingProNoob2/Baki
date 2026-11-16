FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /baki-notify .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 baki
USER baki
WORKDIR /data
COPY --from=build /baki-notify /usr/local/bin/baki-notify
ENV BAKI_NOTIFY_CONFIG=/data/config.json
CMD ["baki-notify"]
