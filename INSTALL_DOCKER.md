# Install MediaPager with Docker

This guide covers the supported Docker Compose deployment. The default stack uses SQLite and
requires no PostgreSQL setup. A bundled PostgreSQL stack is available if you prefer it.

## Requirements

- Docker Engine with the Compose plugin, or Docker Desktop.
- Enough free space for the application data volume and your catalog media.

## Start the default SQLite stack

```sh
git clone --depth 1 https://github.com/MediaPager/MediaPager.git
cd MediaPager
cp .env.example .env
docker compose up -d
docker compose logs -f mediapager
```

Open `http://localhost:8080`. The first startup applies database migrations and creates the
configured seed super-admin if there is no existing one. The generated temporary password is
printed in the API log; retrieve it with `docker compose logs mediapager`, sign in, and change it.

Compose creates a persistent `mediapager-data` volume mounted at `/data`. Its application data
layout is:

```text
/data/db/                     SQLite database
/data/artwork/posters/        locally stored poster files
/data/artwork/backgrounds/    locally stored backdrop files
/data/config/                 runtime settings and plugin catalog state
/data/keys/                   signing and Data Protection key files
/data/tools/                  managed SDK, ffmpeg, and browser tools
/data/plugins/community/      installed community plugins
/data/plugins/official/       installed optional official plugins
/data/cache/                  application caches
```

The app image is read-only at runtime. Persistent writes go to `/data`; temporary build and
worker files use `/tmp`.

## Catalog media is separate from application data

MediaPager does not copy catalog media into its database or artwork folders. Each catalog
points to a folder path that the API process can access. Compose mounts the host folder selected
by `MEDIAPAGER_MEDIA_PATH` at `/mnt/media` (default `./media`). For example, place files on the
host at:

```text
./media/
├── Movies/
└── TV/
```

Then create catalogs using the **container paths** `/mnt/media/Movies` and `/mnt/media/TV`.
For a large library, use a dedicated host or NAS mount so the media remains easy to find and
share with other applications. It is also possible to put media under `/data/media` and point a
catalog there, but that mixes large user-owned media with application-managed files.

Set `MEDIAPAGER_MEDIA_PATH` in `.env` to another host directory. For several media roots, edit
the Compose file to bind each host directory to its own container path and use those paths in
the catalogs. Bind mounts should be read/write when plugins need to manage media files.

## Storage settings and overrides

The settings tree is grouped under `Settings` in appsettings and uses matching environment
names with `__` for each nested section. Compose sets the data root to `/data`; relative storage
paths resolve under that root. For example:

```text
MEDIAPAGER_Settings__Storage__Root=/data
MEDIAPAGER_Settings__Storage__Artwork__PosterDirectory=/data/artwork/posters
MEDIAPAGER_Settings__Storage__Artwork__BackgroundDirectory=/data/artwork/backgrounds
```

Environment variables override runtime settings for editable application options; those values
are stored in the selected database. Database connection details are deployment configuration
only: set them in Compose environment variables or appsettings, not in the Settings UI. The API
keeps a protected copy in `/data/config/database-bootstrap.json` so it can reconnect before the
database opens. Change the deployment configuration and restart the container to switch database
provider or location. Switching providers selects another database and does not transfer account
or catalog rows.

`MEDIAPAGER_GIT_SSH_PRIVATE_KEY_PATH` remains available as a legacy fallback. The preferred
method for private plugin repositories is the super-admin SSH key field in Settings, which
stores the key encrypted in the data database.

Other useful Compose substitutions in `.env`:

| Variable | Default | Purpose |
|---|---:|---|
| `MEDIAPAGER_IMAGE` | `mediapager/mediapager:latest` | Image to run. |
| `MEDIAPAGER_PORT` | `8080` | Host port mapped to container port `5000`. |
| `MEDIAPAGER_BASE_URL` | `http://localhost:8080` | Email link base URL fallback; the saved Site URL setting takes precedence. |
| `MEDIAPAGER_DATA_ROOT` | `/data` | Persistent application-data mount point. If changed, mount a persistent volume at the new path too. |
| `MEDIAPAGER_MEDIA_PATH` | `./media` | Host media directory mounted at `/mnt/media`. |
| `MEDIAPAGER_SEED_USER` | `admin@mediapager.local` | Initial super-admin email, only used on an empty account database. |
| `MEDIAPAGER_SEED_PASS` | generated | Optional first-run password. Keep it secret. |
| `MEDIAPAGER_EKEY` | generated | Optional stable JWT signing key; at least 32 UTF-8 bytes. Keep it secret. |

For a custom Compose deployment, the API accepts names such as
`MEDIAPAGER_Settings__Db__Provider`, `MEDIAPAGER_Settings__Db__Host`,
`MEDIAPAGER_Settings__Db__Catalog`, `MEDIAPAGER_Settings__Storage__Tools__Directory`, and
`MEDIAPAGER_Settings__Storage__Plugins__CommunityDirectory` directly.

## Use the bundled PostgreSQL stack

The PostgreSQL stack keeps its database in a separate `mediapager-postgres` volume and
application state in `mediapager-data`:

```sh
cp .env.example .env
# Set POSTGRES_PASSWORD in .env before starting.
docker compose -f docker-compose.postgres.yml up -d
docker compose -f docker-compose.postgres.yml logs -f mediapager
```

The Compose network keeps PostgreSQL private to the stack. The API waits for the database health
check and applies PostgreSQL migrations. The stack sets `Settings:Db:Provider=PostgreSQL`, host,
port, database name, and user from `POSTGRES_*` values.

For an external PostgreSQL server with the regular Compose file, set
`MEDIAPAGER_DATABASE_PROVIDER=PostgreSQL` and
`MEDIAPAGER_AUTH_CONNECTION_STRING=Host=<reachable-host>;Port=5432;Database=<name>;Username=<user>;Password=<password>`
in `.env`. `localhost` inside the container refers to the MediaPager container, not the Docker
host.

SQLite and PostgreSQL are separate databases. Switching stacks does not copy accounts, runtime
settings, or catalog records.

## Portainer and NAS container managers

Deploy `docker-compose.yml` from Portainer Stacks or the NAS Compose/Container Station screen.
Leave the named data volume enabled. Set `MEDIAPAGER_PORT` if the default host port is occupied;
set `MEDIAPAGER_MEDIA_PATH` to the host media directory. When using a NAS path, map that path to
`/mnt/media` and enter `/mnt/media/...` in MediaPager catalogs.

## Upgrade, backup, and restore

To update the default stack:

```sh
docker compose pull
docker compose up -d
```

`docker compose down` retains named volumes. **Do not use `docker compose down -v` unless you
intend to delete the database, settings, artwork, tools, and installed plugin data.**

The data volume contains the database, locally stored artwork, configuration, keys, tools, and
installed plugins. Back up `mediapager-data` before upgrades or database changes. Back up catalog
media separately from its host or NAS location. Keep signing and Data Protection key files with
the database backup; without them, protected settings and existing JWT sessions may not be
recoverable.

When upgrading an older Compose installation, the entrypoint copies the old managed-tool and
community-plugin volumes into `/data` once and leaves the old volumes intact. Keep those old
volumes until you have confirmed the new installation works and completed a backup.

## Troubleshooting

- **Cannot open the site:** run `docker compose logs mediapager`; check that the host port is free.
- **First-run password not known:** read it from `docker compose logs mediapager`.
- **Catalog path not found:** use the path inside the container (for example `/mnt/media/Movies`),
  not the host path.
- **PostgreSQL is unavailable:** check `docker compose -f docker-compose.postgres.yml logs postgres`
  and confirm `POSTGRES_PASSWORD` is set.
- **Plugin install fails:** inspect the API log for manifest/build details; configure the
  super-admin Git SSH key for private repositories.
- **Disk usage is high:** `/data` contains app-managed state; check catalog media separately at
  the host/NAS mount selected for each catalog.
