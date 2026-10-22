# Home Assistant passes the add-on's version as BUILD_VERSION, so bumping
# `version` in config.yaml is all it takes to move to a new app release.
ARG BUILD_VERSION
FROM ghcr.io/yozko/secretsanta:${BUILD_VERSION}

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl jq \
  && rm -rf /var/lib/apt/lists/*

COPY run.sh tailscale-update.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/tailscale-update.sh

# run.sh starts Tailscale and the Funnel, then the app through the image's own
# entrypoint (which drops root before running it).
ENTRYPOINT []
CMD ["/usr/local/bin/run.sh"]
