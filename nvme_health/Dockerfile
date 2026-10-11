# Image of the NVMe Health add-on: HA Alpine base (s6-overlay, bashio, jq)
# plus smartmontools to read the drive and mosquitto-clients to publish to MQTT.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
FROM ${BUILD_FROM}

RUN apk add --no-cache \
        smartmontools \
        mosquitto-clients

COPY rootfs /

RUN chmod a+x \
        /usr/bin/nvme_health \
        /etc/services.d/nvme_health/run \
        /etc/services.d/nvme_health/finish

LABEL \
    org.opencontainers.image.title="Home Assistant add-on: NVMe Health" \
    org.opencontainers.image.description="NVMe SSD SMART/health monitoring via MQTT discovery" \
    org.opencontainers.image.licenses="MIT"
