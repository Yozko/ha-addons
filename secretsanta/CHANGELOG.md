# Changelog

## 0.2.2

- web: admin link for tailnet visitors; login page links back to participants

## 0.2.1

- web: admin over HTTPS through Tailscale Serve; admin sign-in lasts 3 hours
- web: Debian 13 base image with security updates, without npm
- web: home page states, rules link, notice when names were seen, dark only
- web: spoiler-free admin draw page, past years by hand, and a rules page
- web: presents with photos, versions, a family photo library and live updates
- web: storage limit, streamed uploads, and backups that include photos
- web: npm run release -y skips the confirmation question

## 0.2.0

- web: new links sign out old devices; not-found page leads home; ✏️ rename icons

## 0.1.3

- web: participant pages show this year, clearer device saving, paste-a-link field
- web: admin links that can be shown and copied again, renaming, draw opens this year
- web: fix form posts through the Tailscale Funnel; redirect stray addresses

## 0.1.2.1

- Optional settings no longer need a value: an empty public_url was rejected
  as "expected a URL".

## 0.1.2

- First version of the add-on: the Secret Santa app published through
  Tailscale Funnel, with Tailscale updates checked by SHA-256 and rolled back
  if they fail.
