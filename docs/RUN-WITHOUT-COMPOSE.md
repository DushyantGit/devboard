# Running DevBoard without Docker Compose — the hard way (and why Compose exists)

`docker compose up` is one command because Compose does a lot of work for you:
it creates a network, names the containers so they can find each other, wires
in environment variables, and starts things in the right order.

This guide does all of that **by hand** with plain `docker` commands. It's more
verbose on purpose — once you feel the manual steps, the value of the
`docker-compose.yml` file (and `make up`) is obvious.

> You would not run a real project this way. This is a teaching exercise.

Run everything from the repo root (`devboard/`, on the `advanced` branch).

## The one rule that makes it work: names

Two containers find each other **by name** on a user-defined Docker network:

- the backend connects to host `postgres` (see `POSTGRES_URL`)
- the frontend's Vite preview proxy forwards `/api` to host `backend`
  (see `preview.proxy` in `frontend/vite.config.js`)

So the containers **must** be named `postgres` and `backend`. And name-based
DNS only works on a **user-defined** network — not Docker's default bridge.
That's why step 1 is creating a network.

## Steps

```bash
# 0. Build the two images (Compose did this from `build: ./backend` etc.)
docker build -t devboard-backend ./backend
docker build -t devboard-frontend ./frontend

# 1. Create a user-defined network → containers resolve each other by name
docker network create devboard-net

# 2. Postgres — name it `postgres`, mount the init SQL + a data volume
docker run -d --name postgres --network devboard-net \
  -e POSTGRES_USER=devboard \
  -e POSTGRES_PASSWORD=devboard \
  -e POSTGRES_DB=devboard \
  -v devboard-pgdata:/var/lib/postgresql/data \
  -v "$PWD/init/postgres":/docker-entrypoint-initdb.d:ro \
  -p 5432:5432 \
  postgres:16-alpine

# 3. Backend — name it `backend` (the frontend proxy targets this name)
#    POSTGRES_URL is passed explicitly here (see the note at the bottom).
docker run -d --name backend --network devboard-net \
  -e PORT=8080 \
  -e POSTGRES_URL="postgres://devboard:devboard@postgres:5432/devboard?sslmode=disable" \
  -p 8081:8080 \
  devboard-backend

# 4. Frontend — vite preview serves on 4173 and proxies /api → backend:8080
docker run -d --name frontend --network devboard-net \
  -p 8080:4173 \
  devboard-frontend
```

## Verify

```bash
curl -s http://localhost:8081/health                    # backend  → {"status":"ok"...}
curl -s http://localhost:8080/ | grep -o '<title>.*</title>'   # SPA served
curl -s "http://localhost:8080/api/projects"            # frontend → /api → backend → postgres
open http://localhost:8080                              # the app
```

## Teardown

```bash
docker rm -f frontend backend postgres
docker network rm devboard-net
docker volume rm devboard-pgdata     # only if you want to wipe the DB
```

## Compose → manual, mapped

| Compose did for you | You did by hand |
| --- | --- |
| implicit `devboard_default` network | `docker network create devboard-net` + `--network` on every run |
| service name = DNS name | `--name postgres` / `--name backend` (must match `POSTGRES_URL` and the vite `preview.proxy`) |
| `environment:` / `.env` substitution | a `-e KEY=VALUE` for each variable |
| `ports:` | `-p host:container` on each run |
| `volumes:` (data + init mount) | `-v devboard-pgdata:...` and `-v "$PWD/init/postgres":...:ro` |
| `depends_on` | start in order yourself: postgres → backend → frontend |

## Two gotchas

- **Order matters.** Start `backend` before `frontend`, and `postgres` first.
  The backend has a retry loop, so it tolerates Postgres still warming up.
- **Init SQL only runs on a fresh volume.** `init/postgres/*.sql` execute only
  when `devboard-pgdata` is empty. To re-seed: `docker volume rm devboard-pgdata`
  and re-run step 2. (Compose: `make reset`.)

> **Why `-e POSTGRES_URL=...` instead of `--env-file .env`?** In Compose, the
> backend's `POSTGRES_URL` is *assembled* from the `POSTGRES_*` parts inside
> `docker-compose.yml`. It isn't a line in `.env`, so `--env-file .env` alone
> would not give the backend its connection string — you pass it explicitly.
