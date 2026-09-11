# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.1] - 2026-09-11

### Fixed

- **The socket proxy is watched and scanned like every other pinned image.** It
  was added as a fourth image and then left out of both the daily freshness
  check and the Trivy matrix. A pin nobody watches goes stale in silence, and
  this is the one container in the stack holding the Docker socket — the last
  image that should be scanned by nobody.

  Found by the fleet conformance rule that asserts every digest-pinned image
  has a freshness job behind it. The gap was invisible from inside this
  repository, where every build was green.

## [1.0.0] - 2026-09-10

First release. A production deployment of Dozzle behind Traefik, built to the
fleet standard established in
[keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose).

### Added

- **Dozzle v10.10 behind Traefik with Let's Encrypt TLS.** Four images pinned by
  `tag@sha256:<digest>` in the compose `x-images` block: the application, a
  Docker socket proxy, Traefik, and a plain alpine used by both the init
  container and the backups sidecar.
- **The stack refuses to start without authentication.** Dozzle's own default is
  `DOZZLE_AUTH_PROVIDER=none`, which means an unauthenticated reader of every
  log line on the host: connection strings, tokens printed at startup, the
  bodies of failed requests. Most compose files in circulation leave it there
  and publish the result. The init container either builds `users.yml` from a
  hash in `.env` or stops the deploy with the exact command to generate one,
  before anything is listening. CI asserts on every run that an anonymous
  visitor is redirected to a login page and that the generated credentials are
  accepted by the token endpoint.
- **Dozzle never gets the Docker socket.** Its own security page says a
  container with that socket has root on the host unless restricted, and `:ro`
  on the mount is cosmetic — the API is root-equivalent whichever way the file
  is mounted. A socket proxy holds it instead and forwards only the endpoints
  Dozzle needs, with `POST` denied. Measured and asserted every run:
  `GET /containers/json` answers 200, `POST /containers/<id>/restart` answers
  403, log streaming works, and the Dozzle container has no socket among its
  mounts.
- **Container actions as an opt-in override file.** Restart and stop buttons
  need Dozzle's setting *and* the proxy's `POST` permission, so both live in
  `container-actions.override.yml` — setting one without the other silently
  does nothing, which is a worse outcome than either choice made deliberately.
- **No override path for `DOZZLE_ENABLE_SHELL`, on purpose.** A restart button
  is a restart button; a browser shell inside the container holding your
  database credentials is arbitrary command execution on your host.
- **CI generates the password hash with the command the README gives you.**
  Not a shortcut: running the documented instruction is how it stays true. If
  upstream changes the generator's flags or its output, the build is what
  notices rather than somebody following a stale README.
- **A backup loop that reads its own archive back before naming it a backup**,
  an end-to-end suite that requires `users.yml` in the archive by name, a
  restore script, `update.sh`, `cap_drop: ALL` on every service, resource
  limits and reservations, and OpenSSF Scorecard.

### Notes

- **The Dozzle image is distroless**: no shell, no `wget`, no package manager,
  only the `/dozzle` binary. The init container therefore runs a plain alpine
  — writing four lines of YAML does not need Dozzle — and CI asks the backups
  sidecar about the proxy rather than asking Dozzle, which cannot be asked.
  The first draft used the Dozzle image for the init container and failed with
  `stat /bin/sh: no such file or directory`.
- **A literal `$$` inside an unquoted heredoc is the shell's PID.** The CI
  step that writes the test `.env` substitutes the bcrypt hash into the script
  with `${{ … }}`, so bash saw the text `$$2a$$11$$…` — doubled for Compose —
  inside a heredoc that has to stay unquoted because other variables in it must
  expand. Every `$$` became the process id, and Dozzle refused the password
  against a user file that looked entirely plausible. The credential lines are
  appended with `printf '%s'` from an environment variable now, and the step
  asserts the written value still starts with a doubled bcrypt prefix.
- **`/info` has to be on the proxy's allow-list, and leaving it off fails
  quietly.** Without it Dozzle reports the host as `available: false` with no
  CPU count, no memory figure and no daemon version — while the very next log
  line still says "Connected to Docker". The first version of this template
  shipped that way and nothing in CI noticed, because every assertion was about
  what the proxy answered rather than about what Dozzle made of it. There is
  one about that now.
- **Dozzle's container tags carry the leading `v`** (`v10.10.0`), unlike most
  of this fleet. The freshness check compares the git tag as it comes rather
  than stripping it.
- **Traefik's idle timeout is an hour here, not 180 seconds.** A live log tail
  is a response that never ends, and the default would close it during any
  quiet stretch.
- **There is no Buffering middleware, deliberately.** Traefik streams bodies
  unless one is attached; attaching it is what turns buffering on, and `0` on
  its limits means *no size ceiling*, not *off*. For a log tail that means
  seeing nothing, ever. Measured against a response that takes four seconds to
  produce: 0.03s to the first byte without it, 4.15s with it.

[Unreleased]: https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/releases/tag/v1.0.1
[1.0.0]: https://github.com/heyvaldemar/dozzle-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
