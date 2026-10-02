# Khanya production release process

Khanya production is image-only. The production VPS does **not** pull the
application repository and does **not** build Docker images.

## Release flow

1. Changes are merged into `main`.
2. GitHub Actions `CI` must pass for that exact commit.
3. `Khanya Release Images` automatically builds the FastAPI image from that
   tested commit and publishes:
   `ghcr.io/ithute-stak/khanya-pos-api:<40-character-main-sha>`.
4. Production remains unchanged until an operator explicitly deploys the
   tested image.
5. The VPS pulls the immutable GHCR image, backs up PostgreSQL, runs Alembic
   migrations from that image, restarts the API/outbox worker, and verifies
   health.

Normal production deployment never runs `git pull` or `docker build`.

## VPS runtime directory

The recommended source-free runtime directory is:

```text
/opt/khanya-pos
```

It needs only:

```text
.env
compose.images.yaml
scripts/deploy-production-manual.sh
scripts/deploy-production-latest.sh
releases/
backups/
```

The database, Redis and object-store data remain in Docker volumes.

## One-time setup

Authenticate Docker to GHCR with an account/token that can read the package:

```bash
sudo docker login ghcr.io
```

Install the runtime compose file and the two deployment helpers into
`/opt/khanya-pos`, then:

```bash
sudo chmod 700 /opt/khanya-pos/scripts/deploy-production-*.sh
```

This is a one-time runtime setup. The application repository does not need to
exist on the VPS.

## Deploy current tested main

```bash
cd /opt/khanya-pos
sudo ./scripts/deploy-production-latest.sh
```

The helper verifies that the current `main` SHA has a successful
`Khanya Release Images` workflow before it will deploy.

## Deploy an exact tested SHA

```bash
cd /opt/khanya-pos
sudo ./scripts/deploy-production-manual.sh <40-character-release-sha>
```

The deployment performs:

```text
docker pull ghcr.io/ithute-stak/khanya-pos-api:<sha>
PostgreSQL backup
Alembic migration using the pulled image
API cutover
outbox-worker cutover
health verification
```

It does not fetch application source.

## Optional global pull command

A VPS wrapper may expose:

```bash
pull khanya latest
```

That wrapper should call:

```bash
/opt/khanya-pos/scripts/deploy-production-latest.sh
```

so `latest` means the current tested `main` SHA, not a mutable Docker tag.
