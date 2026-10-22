# The app image's version comes from build.yaml (APP_VERSION), so the add-on
# can get its own fixes without a new app release.
ARG APP_VERSION
FROM ghcr.io/yozko/secretsanta:${APP_VERSION}

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
