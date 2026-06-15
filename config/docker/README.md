# Docker templates

The agents copy these into a project. They target **OrbStack** (the only engine
this setup uses) but are standard Docker, so they work anywhere.

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage, non-root Node build (+ Next.js standalone variant in comments) |
| `docker-compose.yml` | Local `app` + Postgres + Redis (+ commented Qdrant for RAG/ML) |
| `.dockerignore` | Keep the build context (and image) small |

## Use them

```bash
cp config/docker/{Dockerfile,docker-compose.yml,.dockerignore} .   # into your project
echo "POSTGRES_PASSWORD=devpassword" >> .env

docker compose up -d        # start app + Postgres + Redis
hadolint Dockerfile         # lint the Dockerfile for correctness/size
docker build -t myapp .     # build the image
dive myapp                  # inspect layers, find wasted space
```

With OrbStack, **open the OrbStack app** to see running containers, live logs,
and a Files tab — or reach a service at `<service>.myapp.orb.local`.

## Build for deployment (amd64 from your arm64 Mac)

```bash
docker buildx create --use                              # one-time: a multi-arch builder
docker buildx build --platform linux/amd64 -t <tag> --push .
```
Multi-arch builds must `--push` (they can't `--load` into the local store).

## Ship it

```bash
fly auth login              # one-time
fly launch                  # containerize + deploy to fly.io
```

## Dev dependencies

None to install — `docker` (OrbStack), `hadolint`, `dive`, and `fly` are
installed system-wide by `12-containers.sh`.
