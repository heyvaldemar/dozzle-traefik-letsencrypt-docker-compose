# Dozzle + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository deploys Dozzle (live Docker logs for every container, in a browser, with search and multi-container tail) behind Traefik with automatic Let's Encrypt TLS.

Dozzle answers one question — *what actually broke?* — and it answers it without a log shipper, a storage backend or an index, because it streams from the Docker daemon rather than collecting anything. The payoff is at eleven at night on a phone: `docker logs -f` over SSH works too, but searching four containers at once from a browser takes thirty seconds instead of ten minutes.

It is also the most dangerous container you will deploy, and this template is built around that.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose
cd dozzle-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create dozzle-network

# 3. Generate a password hash for your account
docker run --rm amir20/dozzle:v11.0.1 generate \
  --name 'Your Name' --email you@example.com \
  --password 'YOUR_STRONG_PASSWORD' yourusername

# 4. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: DOZZLE_HOSTNAME, TRAEFIK_HOSTNAME, TRAEFIK_ACME_EMAIL,
#   TRAEFIK_BASIC_AUTH, DOZZLE_ADMIN_USERNAME, DOZZLE_ADMIN_PASSWORD_HASH.
#   Paste the hash from step 3 with every $ DOUBLED to $$.

# 5. Deploy
docker compose -f dozzle-traefik-letsencrypt-docker-compose.yml -p dozzle up -d
```

Step 3 is not optional and the stack enforces it. Skip it and the deploy stops with this, before anything is listening:

```
ERROR: Dozzle would start with no authentication.

  There is no /data/users.yml, and DOZZLE_ADMIN_USERNAME and
  DOZZLE_ADMIN_PASSWORD_HASH are not both set in .env.

  Dozzle shows every log line from every container on this
  host. That includes connection strings, tokens printed at
  startup, and the bodies of failed requests. Unauthenticated,
  it hands all of that to whoever finds the hostname.
```

Dozzle's own default is `DOZZLE_AUTH_PROVIDER=none`. Most compose files you will find leave it there, and publish the result. CI here asserts on every run that an anonymous visitor is sent to a login page and that the generated credentials are accepted — so if that default ever came back, or the init container stopped writing a user file, the build is what notices.

### What success looks like

```bash
docker compose -f dozzle-traefik-letsencrypt-docker-compose.yml -p dozzle ps
curl -sk -o /dev/null -w '%{http_code}\n' "https://${DOZZLE_HOSTNAME}/"
# 307 — an anonymous visitor is redirected to the login page
```

`ps` shows `dozzle`, `dockerproxy` and `traefik` running, `backups` running with no health check of its own, and `init-auth` exited 0.

### Common first-deploy issues

- **The deploy stops at `init-auth`.** That is the message above; step 3 was skipped, or the hash was pasted without doubling its `$`.
- **The credentials are rejected although the hash looks right.** Compose ate the `$` signs. `docker compose -p dozzle exec backups cat /data/users.yml` shows what was actually written; a truncated-looking hash is the giveaway. Delete the `dozzle-data` volume, fix `.env`, deploy again.
- **Traefik answers `404 page not found` and its log says nothing.** Traefik does not route to a container whose health check is failing, so a broken probe looks exactly like a missing route. Check the health column in `ps`.
- **Cert issuance fails.** DNS has not propagated, or port 80 is not reachable from the internet.
- **Networks not found.** Step 2 was skipped.

## Dozzle never gets the Docker socket

Dozzle's own security page is blunt about the usual arrangement: a container with the Docker socket has, unless restricted, root on the host. And `:ro` on that mount is cosmetic — the API is root-equivalent whichever way the file is mounted, because the privilege is in what the API can do, not in who can write the socket file. Nearly every Dozzle compose file in circulation mounts it anyway.

Here a socket proxy holds it and forwards exactly the endpoints Dozzle needs, over an internal network with nothing published to the host. `POST` is denied, which is what makes it read-only: a compromised Dozzle can list containers and read logs, and it cannot start, stop, delete or exec anything at all.

Measured on this stack rather than assumed, and asserted on every CI run:

| through the proxy | answer |
| :--- | :--- |
| `GET /containers/json` | `200` |
| `POST /containers/<id>/restart` | `403` |
| log streaming | works |

The Dozzle container's mount list is checked too, because the cheapest way for this property to disappear is someone adding the socket back "just for now".

## Container actions, if you want them

Restart and stop buttons in the log view are off. Turning them on means turning on `POST` at the proxy as well, and both live in one file so that setting one without the other cannot silently do nothing:

```bash
docker compose \
  -f dozzle-traefik-letsencrypt-docker-compose.yml \
  -f container-actions.override.yml \
  -p dozzle up -d
```

Read the trace and bounce the container in the same tab is a real convenience at two in the morning. It is also a real change to what a stolen session cookie is worth, and the file says so.

**There is no override file for `DOZZLE_ENABLE_SHELL`, deliberately.** A restart button is a restart button; a browser shell inside the container holding your database credentials is arbitrary command execution on your host. You have SSH.

## Put it behind more than one door if it faces the internet

Dozzle's login is a login form on the public internet in front of every log line your machine produces. That is better than nothing by an enormous margin, and it is still one door. If this hostname is reachable from outside your network, an identity-aware proxy in front of it — Cloudflare Access, Authelia, a VPN — is the arrangement to aim for. Enable a second factor on the account either way.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted and proven — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen.

If you run with the actions override, add it to your own `up` command after the update: `update.sh` starts the base file only.

## Supply chain trust

Four images pinned to `tag@sha256:<digest>` as interpolation defaults in the compose `x-images` block:

- [`amir20/dozzle`](https://hub.docker.com/r/amir20/dozzle): the application, latest stable (v11.1.0)
- [`ghcr.io/tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy): the only container that touches the socket
- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy
- [`alpine`](https://hub.docker.com/_/alpine): the init container and the backups sidecar

`git pull` alone delivers the tested combination; an `*_IMAGE_TAG` variable in `.env` overrides deliberately.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. Nested defaults need Docker Compose v2.5 or newer (2022).

The daily `check-pin-freshness` CI job re-resolves each pin against its registry and compares the pinned Dozzle and Traefik versions against the latest upstream releases. Note that Dozzle's container tags carry the leading `v` (`v11.0.1`), unlike most images. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## Production checklist

- [ ] **Generate a real password** in step 3 and enable a second factor if anything in front of this supports one.
- [ ] **Regenerate the Traefik dashboard hash.** The one in `.env.example` is a placeholder.
- [ ] **Decide whether this should face the internet at all**, and put an identity-aware proxy in front of it if it does.
- [ ] **Leave the actions override off** unless you have read what it changes.
- [ ] **Host-mount the backup volume.** By default the archives land in a named volume: if the host dies, they die with it.
- [ ] **Remember what Dozzle can see.** Every container's stdout, including whatever your applications print on a bad day. Auditing that is a separate job and this makes it easier, not safer.

## Backups and restore

The `backups` container archives `/data` on a loop — a 30-minute warm-up, a 24-hour interval, 7-day retention, all overridable in `.env`. That directory is small and entirely irreplaceable: `users.yml`, and each user's interface settings. No logs are in it; Dozzle stores none.

Each archive is written to a `.partial` name, **read back with `tar -tzf`**, and only then renamed. The read-back is not decoration: BusyBox tar, which is what an alpine image ships, returns exit code 1 both for "a file changed while I was reading it" and for "I could not write the output at all", and an archive truncated after tar exited still carries exit status 0. Trusting the exit code alone renames an unreadable file into place and calls it a backup.

Restore with the interactive script:

```bash
chmod +x ./*.sh
./dozzle-restore-data.sh
```

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. They are small because Dozzle is small — it streams rather than stores, so the numbers barely move with the number of containers. Override any of them in `.env` and the override survives every `git pull`. If a service is OOM-killed, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true`. Dozzle, the init container and the backups sidecar run with `cap_drop: [ALL]`; Traefik adds back `NET_BIND_SERVICE` and the sidecar the three it needs to write archives it owns. Dozzle adds back nothing: it is one Go binary serving HTTP and talking to a TCP endpoint.

The Dozzle image is distroless — no shell, no `wget`, no package manager — which is why the init container runs a plain alpine and why CI asks the backups sidecar about the proxy rather than asking Dozzle.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC: shellcheck and actionlint, Trivy scans of all four pinned images, the daily freshness check, and a deploy job that generates the admin hash **with the exact command this README gives you** — so that instruction stays true rather than going stale — and then requires the login page to be served, an anonymous visitor to be redirected to it, the generated credentials to be accepted by the token endpoint, the Dozzle container to have no Docker socket among its mounts, the proxy to answer `403` to a POST and `200` to a GET, an archive to be produced and to carry `users.yml` by name, eight backup and restore scenarios to pass, and Dozzle to come back up on the data directory the restore test replaced underneath it.

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

Run it on a staging copy, not on production: it stops the application and empties the data directory.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- The stack will not start without authentication configured.
- The Docker socket is held by a proxy that denies every write, and Dozzle does not have it.
- The interactive shell feature is off and has no opt-in path here.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
