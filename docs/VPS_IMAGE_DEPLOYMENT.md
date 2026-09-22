# Khanya POS — Manual VPS Deployment

Khanya follows the same production model used by Lelefa Chambers: GitHub Actions builds the application image, while the VPS only pulls tested images and starts them. The VPS does not build the FastAPI application.

## Production endpoint

```text
https://api.khanya.ithute.co.ls
```

The API itself listens on container port `8009`. The shared Caddy edge reaches it over the external Docker network `public-edge` using the alias `khanya-api`.

The optional VPS loopback mapping is:

```text
127.0.0.1:18009 -> khanya-api:8009
```

PostgreSQL, Redis and MinIO are not published publicly.

## Published image

```text
ghcr.io/ithute-stak/khanya-pos-api:latest
```

Each release is also tagged with the tested commit:

```text
ghcr.io/ithute-stak/khanya-pos-api:sha-<shortsha>
```

The outbox worker uses the same image with a different command.

## Release flow

```text
merge to main
    |
    v
CI succeeds
    |
    v
Publish Khanya API Image
    |
    +--> ghcr.io/ithute-stak/khanya-pos-api:latest
    +--> ghcr.io/ithute-stak/khanya-pos-api:sha-...
    |
    v
manual VPS pull + migration + restart
```

A failed CI run does not publish a new production `latest` image.

## 1. DNS

Create this DNS record at the authoritative provider:

```text
A   api.khanya.ithute.co.ls   <VPS_PUBLIC_IPV4>
```

Do not add an AAAA record unless the VPS is actually configured for public IPv6 on ports 80/443.

## 2. One-time VPS preparation

Clone the repository once:

```bash
cd ~
git clone https://github.com/ithute-stak/khanya-pos.git
cd khanya-pos
cp .env.production.example .env
chmod 600 .env
```

Edit `.env` and replace every `CHANGE_THIS_*` value. Use long random production secrets. Do not commit `.env`.

If the GHCR package is private, authenticate Docker once with a token that has `read:packages`:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u ithute-stak --password-stdin
```

Do not put that token in the repository or the application `.env` file.

## 3. Shared Caddy edge

Khanya intentionally reuses the existing shared VPS Caddy and `public-edge` network used by Lelefa Chambers.

Confirm them first:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E 'caddy|NAMES'
docker network inspect public-edge >/dev/null
```

The committed route is:

```text
deploy/caddy/khanya.Caddyfile
```

On the current Ithute shared edge, product routes are persisted under `/data/product-routes`. Install the route into the shared Caddy container/volume using the same method as the other products, for example:

```bash
docker cp deploy/caddy/khanya.Caddyfile ithute-caddy-1:/data/product-routes/khanya.caddy
docker exec ithute-caddy-1 caddy validate --config /etc/caddy/Caddyfile
docker exec ithute-caddy-1 caddy reload --config /etc/caddy/Caddyfile
```

Do not start a second reverse proxy on ports 80/443.

## 4. Normal manual deployment

After CI has published the API image:

```bash
cd ~/khanya-pos
git checkout main
git pull --ff-only origin main
chmod +x scripts/deploy-images.sh
./scripts/deploy-images.sh
```

The script performs this sequence:

```text
pull API + worker + infrastructure images
        |
        v
start PostgreSQL + Redis + MinIO
        |
        v
wait for PostgreSQL
        |
        v
run Alembic upgrade head once
        |
        v
start API
        |
        v
wait for API health
        |
        v
start/verify outbox worker
```

No `docker build` occurs on the VPS.

## 5. Verify deployment

Local VPS checks:

```bash
docker compose --env-file .env -f compose.images.yaml ps
curl -fsS http://127.0.0.1:18009/api/v1/health
curl -fsS http://127.0.0.1:18009/api/v1/health/ready
```

Public checks after DNS/Caddy are active:

```bash
curl -fsS https://api.khanya.ithute.co.ls/api/v1/health
curl -fsS https://api.khanya.ithute.co.ls/api/v1/health/ready
```

Expected readiness includes PostgreSQL and Redis as ready.

## 6. Flutter production endpoint

For a physical Android test or production build, compile the client with:

```bash
flutter run \
  --dart-define=KHANYA_API_BASE_URL=https://api.khanya.ithute.co.ls/api/v1
```

Release builds should use the same `KHANYA_API_BASE_URL` value.

## 7. Rollback

Change the image tag in `.env` from `latest` to a previously published immutable tag:

```env
KHANYA_IMAGE_TAG=sha-1a2b3c4
```

Then run:

```bash
./scripts/deploy-images.sh
```

Return to rolling releases by setting `KHANYA_IMAGE_TAG=latest` again.

## 8. Data safety

The production PostgreSQL, Redis and MinIO data live in named Docker volumes. Normal image deployment does not delete those volumes.

Never use `docker compose down -v` during a normal deployment. Back up PostgreSQL and MinIO before schema/storage migrations or destructive maintenance.
