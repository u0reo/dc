FROM golang:1.27-alpine AS builder

ARG CODEX_PROXY_REPO=https://github.com/dvcrn/codex-oauth-proxy.git
ARG CODEX_PROXY_REF=1.1.0

RUN apk add --no-cache git ca-certificates

WORKDIR /src

RUN git clone --filter=blob:none "${CODEX_PROXY_REPO}" . \
    && git checkout "${CODEX_PROXY_REF}" \
    && git rev-parse HEAD

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/codex-oauth-proxy \
    ./cmd/codex-oauth-proxy


FROM alpine:latest

RUN apk add --no-cache ca-certificates wget \
    && addgroup -g 1000 codex \
    && adduser -D -u 1000 -G codex -h /home/codex codex \
    && mkdir -p /config \
    && chown -R 1000:1000 /config /home/codex

COPY --from=builder /out/codex-oauth-proxy /usr/local/bin/codex-oauth-proxy

USER 1000:1000

ENV HOME=/home/codex
ENV XDG_CONFIG_HOME=/config
ENV PORT=9879
ENV ENV=production
ENV DISABLE_HEALTH_LOGS=true

EXPOSE 9879

ENTRYPOINT ["/usr/local/bin/codex-oauth-proxy"]