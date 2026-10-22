# Secret Santa

Family Secret Santa: every participant gets a personal link and sees only the
person they give to. The participant pages are published on the internet
through **Tailscale Funnel** from a separate Tailscale node (`santa`). The
admin pages stay on your local network.

## 1. Tailscale (once)

In the [Tailscale admin console](https://login.tailscale.com/admin):

1. **DNS:** turn on MagicDNS and **HTTPS Certificates**.
2. **Access controls:** add the tag, and allow it to use Funnel. Don't give
   `tag:santa` any grant as a *source*: the node must not reach the rest of
   your tailnet.

   ```jsonc
   "tagOwners": {
     "tag:santa": ["autogroup:admin"],
   },
   "nodeAttrs": [
     { "target": ["tag:santa"], "attr": ["funnel"] },
   ],
   ```
3. **Settings → Keys → Generate auth key:** *Pre-approved*, *Tags:
   `tag:santa`*, not reusable, not ephemeral. Copy the key.

## 2. Configuration

| Option | |
| --- | --- |
| `admin_password` | Password for the admin pages. Required. |
| `tailscale_auth_key` | The key from step 1.3. Only needed for the first start; you can clear it afterwards. |
| `tailscale_hostname` | Name of the Tailscale node, and so of the public address `https://<name>.<tailnet>.ts.net`. Default `santa`. |
| `public_url` | Leave empty to use the Funnel address. Only set it if participants should use a different address. |
| `notify_service` | A Home Assistant notify service, e.g. `mobile_app_my_phone`, for add-on problems: Tailscale updates, rollbacks, failed starts. |
| `notify_webhook_url` | Where the app sends admin notifications (someone tried to sign in on too many devices). See section 4. |

**Network:** port 3001 is the admin pages; keep it on the local network and
never forward it in your router. Port 3000 (the participant pages) should stay
empty: participants reach it through the Funnel.

Turn on **Watchdog** on the add-on's Info tab, so it is restarted if it stops.

## 3. Use

- **Participants:** `https://santa.<tailnet>.ts.net` (shown in the add-on log at start).
- **Admin:** `http://<home-assistant-address>:3001/admin` from your local network
  (or over Tailscale to your Home Assistant).

To move existing data in: export it where it is now (admin → Backup →
Download export, or `npm run export`), then import it here under admin → Backup.

Home Assistant backups include the add-on's data (the database and Tailscale's
state).

## 4. Notifications

**Add-on problems** go to `notify_service` directly.

**App notifications** go to a webhook. Create this automation, then set
`notify_webhook_url` to `http://homeassistant:8123/api/webhook/secretsanta-admin`:

```yaml
alias: Secret Santa admin notification
triggers:
  - trigger: webhook
    webhook_id: secretsanta-admin
    allowed_methods: [POST]
    local_only: true
actions:
  - action: notify.mobile_app_my_phone
    data:
      title: "{{ trigger.json.title }}"
      message: "{{ trigger.json.message }}"
```

## 5. Keeping Tailscale up to date

Every start installs the newest stable Tailscale. It checks the download
against Tailscale's published SHA-256 first, and keeps the previous version.
If a new version does not start, the add-on rolls back, remembers the bad
version and notifies you. A weekly restart is therefore a weekly update:

```yaml
alias: Secret Santa weekly restart
triggers:
  - trigger: time
    at: "04:00:00"
conditions:
  - condition: time
    weekday: [mon]
actions:
  - action: hassio.addon_restart
    data:
      addon: xxxxxxxx_secretsanta   # the add-on's slug, from its page's URL
  - delay: "00:03:00"
  - if:
      - condition: state
        entity_id: binary_sensor.secret_santa_running   # enable it under the Supervisor integration
        state: "off"
    then:
      - action: notify.mobile_app_my_phone
        data:
          message: Secret Santa did not come back after its weekly restart.
```

## 6. Updating

**App releases** (`npm version patch` and `npm run release` in the Secret
Santa repository) update this add-on automatically once the image is built:
the release workflow sets `APP_VERSION` in `build.yaml` and `version` in
`config.yaml` to the new version. Home Assistant then offers the update.

**Add-on-only changes** (run.sh, these docs): add a fourth number to
`version` in `config.yaml` (0.1.2 → 0.1.2.1 → 0.1.2.2) and push. Home
Assistant ranks 0.1.2.1 above 0.1.2 and below the next app release, 0.1.3.
