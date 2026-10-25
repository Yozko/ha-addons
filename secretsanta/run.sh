#!/usr/bin/env bash
# Starts the add-on: Tailscale (its own node, userspace networking), the Funnel
# that publishes port 3000, then the Secret Santa app. If either Tailscale or
# the app stops, the add-on stops too, so Home Assistant's watchdog restarts it.
set -euo pipefail

OPTIONS=/data/options.json
TS_DIR=/data/tailscale
BIN_DIR=$TS_DIR/bin
SOCKET=/run/tailscale/tailscaled.sock

log() { echo "[secretsanta] $*"; }
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }
ts() { "$BIN_DIR/current/tailscale" --socket="$SOCKET" "$@"; }
ts_version() { cat "$BIN_DIR/current/VERSION" 2>/dev/null || echo none; }

# A Home Assistant notification through the Supervisor, if a notify service is set.
notify() {
  log "$1"
  local service
  service=$(opt notify_service)
  [[ -n "$service" && -n "${SUPERVISOR_TOKEN:-}" ]] || return 0
  curl -fsS -m 10 -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg m "$1" '{title: "Secret Santa add-on", message: $m}')" \
    "http://supervisor/core/api/services/notify/${service#notify.}" >/dev/null ||
    log "Could not send the notification"
}

backend_state() { ts status --json 2>/dev/null | jq -r '.BackendState // empty' || true; }

start_tailscaled() {
  mkdir -p "$(dirname "$SOCKET")" "$TS_DIR/state"
  "$BIN_DIR/current/tailscaled" --tun=userspace-networking --statedir="$TS_DIR/state" --socket="$SOCKET" &
  TS_PID=$!
}

# Waits until tailscaled answers (any state); with an argument, until it reaches that state.
wait_for_tailscaled() {
  local want=${1:-} state
  for _ in $(seq 1 60); do
    state=$(backend_state)
    if [[ -n "$state" && (-z "$want" || "$state" == "$want") ]]; then return 0; fi
    sleep 1
  done
  return 1
}

# --- 1. Tailscale binaries -------------------------------------------------
before=$(ts_version)
if ! /usr/local/bin/tailscale-update.sh; then
  if [[ -x "$BIN_DIR/current/tailscaled" ]]; then
    notify "Updating Tailscale failed; keeping version $before."
  else
    notify "Tailscale could not be downloaded, and no earlier version is installed. The add-on cannot start."
    exit 1
  fi
fi
after=$(ts_version)
if [[ "$before" != "$after" && "$before" != none ]]; then notify "Tailscale updated from $before to $after."; fi

# --- 2. Start the daemon, rolling back to the previous version if it misbehaves
start_tailscaled
if ! wait_for_tailscaled; then
  kill "$TS_PID" 2>/dev/null || true
  wait "$TS_PID" 2>/dev/null || true
  if [[ -d "$BIN_DIR/previous" ]]; then
    bad=$(ts_version)
    echo "$bad" >"$BIN_DIR/bad-version"
    rm -rf "$BIN_DIR/failed"
    mv "$BIN_DIR/current" "$BIN_DIR/failed"
    mv "$BIN_DIR/previous" "$BIN_DIR/current"
    notify "Tailscale $bad did not start; rolled back to $(ts_version)."
    start_tailscaled
    wait_for_tailscaled || { notify "Tailscale does not start, even after rolling back."; exit 1; }
  else
    notify "Tailscale $(ts_version) does not start."
    exit 1
  fi
fi

# --- 3. Log in once (the node and its identity are kept in /data) ------------
# Right after starting, the state passes through Starting/NoState; let it settle.
state=""
for _ in $(seq 1 30); do
  state=$(backend_state)
  [[ "$state" == Running || "$state" == NeedsLogin || "$state" == Stopped ]] && break
  sleep 1
done
up_flags=(--hostname="$(opt tailscale_hostname)" --advertise-tags=tag:santa)
if [[ "$state" == NeedsLogin ]]; then
  key=$(opt tailscale_auth_key)
  if [[ -z "$key" ]]; then
    notify "Tailscale is not logged in. Set tailscale_auth_key in the add-on configuration (only needed once)."
    exit 1
  fi
  ts up "${up_flags[@]}" --authkey="$key"
elif [[ "$state" != Running ]]; then
  ts up "${up_flags[@]}"
fi
wait_for_tailscaled Running || { notify "Tailscale did not connect."; exit 1; }

# --- 4. Publish the participant pages (port 3000 only) through the Funnel ----
ts funnel --bg 3000 >/dev/null
dns=$(ts status --json | jq -r '.Self.DNSName // empty')
public_url=$(opt public_url)
public_url=${public_url:-https://${dns%.}}

# The admin pages over HTTPS, for devices on the tailnet only: Serve, not Funnel,
# so port 8443 is never published on the internet.
ts serve --bg --https=8443 http://127.0.0.1:3001 >/dev/null
admin_url="https://${dns%.}:8443"
log "Participants: $public_url   Admin: $admin_url/admin (devices on your tailnet only)"

# --- 5. Start the app -----------------------------------------------------------
export NODE_ENV=production PORT=3000 ADMIN_PORT=3001 DATA_DIR=/data/secretsanta TRUST_PROXY_LOOPBACK=1
export PUBLIC_URL=$public_url ADMIN_PUBLIC_URL=$admin_url
export ADMIN_PASSWORD
ADMIN_PASSWORD=$(opt admin_password)
NOTIFY_WEBHOOK_URL=$(opt notify_webhook_url)
if [[ -n "$NOTIFY_WEBHOOK_URL" ]]; then export NOTIFY_WEBHOOK_URL; fi
cd /app
/app/docker-entrypoint.sh node server.ts &
APP_PID=$!

shutdown() {
  kill -TERM "$APP_PID" "$TS_PID" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

# Stop the add-on as soon as either process ends, so the watchdog restarts both.
set +e
wait -n "$APP_PID" "$TS_PID"
code=$?
if kill -0 "$APP_PID" 2>/dev/null; then
  notify "Tailscale stopped (exit $code); restarting the add-on."
else
  notify "The Secret Santa app stopped (exit $code); restarting the add-on."
fi
kill -TERM "$APP_PID" "$TS_PID" 2>/dev/null
wait
exit 1
