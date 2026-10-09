# MediaPager

<p align="center">
  <img src="https://github.com/MediaPager/MediaPager.App.Ui/blob/master/src/assets/images/icon.png?raw=true" alt="MediaPager play icon" width="160"><br>
  <strong>Self-hosted media, built to be extended</strong>
</p>

MediaPager is a self-hosted media platform composed of an ASP.NET Core API, a Vue 3 +
Quasar web app, a plugin SDK, and independently versioned plugins. Search, metadata,
playback, subtitles, email, and other capabilities are provided through plugins instead
of being hard-wired to one provider. The production container includes both the API and
the built SPA, served from one origin by a single container.

This is the **superproject**. It contains the .NET solution, Dockerfiles, Compose
deployment, and one Git submodule per component. The components are maintained in their
own repositories in the [MediaPager GitHub organization](https://github.com/MediaPager).

## Contents

- [Components and repositories](#components-and-repositories)
- [Architecture](#architecture)
- [Requirements and clone](#requirements-and-clone)
- [Build and run locally](#build-and-run-locally)
- [Environment variables and configuration](#environment-variables-and-configuration)
- [Docker deployment](#docker-deployment)
- [Automatic updates with Watchtower](#automatic-updates-with-watchtower)
- [Plugin development and discovery](#plugin-development-and-discovery)
- [Data, accounts, and operations](#data-accounts-and-operations)
- [Troubleshooting](#troubleshooting)

## Components and repositories

| Path | Repository | Responsibility |
|---|---|---|
| `MediaPager.App.Api` | [MediaPager.App.Api](https://github.com/MediaPager/MediaPager.App.Api) | ASP.NET Core host, authentication, persistence, HTTP APIs, and plugin lifecycle. |
| `MediaPager.App.Core` | [MediaPager.App.Core](https://github.com/MediaPager/MediaPager.App.Core) | Domain services, database model, plugin registry/deployer, and shared infrastructure. |
| `MediaPager.App.PluginContracts` | [MediaPager.App.PluginContracts](https://github.com/MediaPager/MediaPager.App.PluginContracts) | SDK interfaces and DTOs implemented by plugins. |
| `MediaPager.App.Ui` | [MediaPager.App.Ui](https://github.com/MediaPager/MediaPager.App.Ui) | Vue 3 + Quasar single-page web application. |
| `MediaPager.Plugins.Stream.Local` | [MediaPager.Plugins.Stream.Local](https://github.com/MediaPager/MediaPager.Plugins.Stream.Local) | Local playback for media in configured catalogs. |
| `MediaPager.Plugins.Search.Local` | [MediaPager.Plugins.Search.Local](https://github.com/MediaPager/MediaPager.Plugins.Search.Local) | Search across the local library. |
| `MediaPager.Plugins.Search.Tmdb` | [MediaPager.Plugins.Search.Tmdb](https://github.com/MediaPager/MediaPager.Plugins.Search.Tmdb) | TMDB metadata and search. |
| `MediaPager.Plugins.Subtitles.OpenSubtitles` | [MediaPager.Plugins.Subtitles.OpenSubtitles](https://github.com/MediaPager/MediaPager.Plugins.Subtitles.OpenSubtitles) | OpenSubtitles search and subtitle downloads. |
| `MediaPager.Plugins.Subtitles.Subdl` | [MediaPager.Plugins.Subtitles.Subdl](https://github.com/MediaPager/MediaPager.Plugins.Subtitles.Subdl) | Subdl search and subtitle downloads. |
| `MediaPager.Plugins.Email.Smtp` | [MediaPager.Plugins.Email.Smtp](https://github.com/MediaPager/MediaPager.Plugins.Email.Smtp) | SMTP delivery for invitations and password resets. |
| `MediaPager.Plugins.Email.MailGun` | [MediaPager.Plugins.Email.MailGun](https://github.com/MediaPager/MediaPager.Plugins.Email.MailGun) | Mailgun delivery for invitations and password resets. |

The solution file, `MediaPager.slnx`, includes the API, Core, SDK, and buildable official
plugins. The UI has its own Node/npm toolchain. Each path above must be checked out as a
submodule for a complete build.

## Architecture

### Host and interface

- **API** owns HTTP endpoints, accounts, authorization, database migrations, and
  application startup. It loads plugin assemblies and exposes plugin capabilities to the
  web application.
- **Core** owns shared domain/data services and the plugin host. Plugins do not reference
  Core or the API.
- **PluginContracts** is the boundary between host and plugins. Plugins reference the SDK
  and implement one or more capability interfaces.
- **UI** reads `/sources` and `/plugins` and builds navigation, provider browse/detail
  views, actions, and settings from those declarations. Provider screens are not
  individually hard-coded into the SPA.

### Plugin lifecycle

The API has an official plugin directory and a community plugin directory under the plugin
root. Shipped official plugins are built with the API and copied into the official
directory. Other official plugins and community plugins can be installed on demand from
**Settings → Plugins**. At startup, the host loads eligible official plugins and installed
community plugins from those directories.

Official plugin metadata is in `MediaPager.App.Api/plugins.official.json`; recognized
community entries are stored in `plugins.community.json`. The appsettings `Plugins:Required`
lists select which official/community ids are required and which shipped officials are
active. Plugin settings are saved in the application database and read through the SDK's
settings store. Secret fields are redacted in settings responses.

## Requirements and clone

For local development, install:

- Git with submodule support
- .NET 10 SDK
- Node.js 24 and npm
- Docker Engine/Desktop (the dev launcher starts local PostGIS; Compose is used for container deployment)

Clone all repositories with the superproject:

```sh
git clone --recurse-submodules https://github.com/MediaPager/MediaPager.git
cd MediaPager
```

The `.gitmodules` entries use relative sibling URLs and work with HTTPS or SSH clone
transports. To populate submodules in an existing clone:

```sh
git submodule update --init --recursive
```

## Dev Setup (1-2-3)

With Git, the .NET 10 SDK, Node.js 24/npm, and Docker running, start both database variants:

```sh
git clone --recurse-submodules https://github.com/MediaPager/MediaPager.git
cd MediaPager
./dev.sh up
```

Running `./dev.sh` or `./dev.sh help` prints the help text. `./dev.sh up` fills in the
standard local settings when absent, starts a persistent PostGIS container if needed,
installs UI npm dependencies if missing, and runs the SQLite and PostgreSQL variants side
by side:

| Database | API | SPA |
|---|---|---|
| SQLite | `http://localhost:5074` | `http://localhost:5173` |
| PostgreSQL | `http://localhost:5075` | `http://localhost:5174` |

The local PostgreSQL defaults are container `postgis`, user `postgres`, password `password`,
and database `mediapager_dev`. The database and migrations are created automatically. The
PostGIS container and its Docker volume stay running when MediaPager is stopped.
`./dev.sh --refresh` drops both dev databases and recreates them from the current migrations.
On Windows, the local-only `dev.ps1` counterpart has the same commands (`.\dev.ps1 help`,
`.\dev.ps1 up`) but is not included in clones yet.

For an empty database, the launchers seed `admin@mediapager.local` with password
`DefaultPasswordChangeMe` and print those credentials at startup. The seed is only used when
there is no existing super-admin; it does not change passwords in an existing database.

**Optional TMDB metadata/search:** create a TMDB account at
[themoviedb.org](https://www.themoviedb.org/signup), request an API key, and set
`MEDIAPAGER_TMDB_API_KEY` in `~/.MediaPager/dev/credentials.sh`. The launcher announces when
this optional key is missing; the rest of the app still starts. A key entered in Settings
takes precedence over the environment variable.

The local defaults are process-scoped. To customize them persistently, create
`~/.MediaPager/dev/credentials.sh` and add environment assignments such as:

```sh
export MEDIAPAGER_Database__Provider='PostgreSQL'
export MEDIAPAGER_ConnectionStrings__AuthDatabase='Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password'
export MEDIAPAGER_Auth__SigningKey='your_32_byte_sign_key_placeholder_here'
export MEDIAPAGER_DB_PATH="$HOME/.MediaPager/db/mediapager.db"
export MEDIAPAGER_SEED_USER='admin@mediapager.local'
export MEDIAPAGER_SEED_PASS='DefaultPasswordChangeMe'
# Optional: replace with your TMDB API key.
# export MEDIAPAGER_TMDB_API_KEY='PASTE_TMDB_API_KEY_HERE'
```

Windows reads an optional `%USERPROFILE%\.MediaPager\dev\credentials.ps1` file. Create it
with `New-Item -ItemType Directory -Path "$HOME\.MediaPager\dev" -Force` and open it with
`notepad "$HOME\.MediaPager\dev\credentials.ps1"`. Use PowerShell assignments there:

```powershell
$env:MEDIAPAGER_Database__Provider = 'PostgreSQL'
$env:MEDIAPAGER_ConnectionStrings__AuthDatabase = 'Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password'
$env:MEDIAPAGER_Auth__SigningKey = 'your_32_byte_sign_key_placeholder_here'
$env:MEDIAPAGER_DB_PATH = (Join-Path $HOME 'AppData\Roaming\MediaPager\db\mediapager.db')
$env:MEDIAPAGER_SEED_USER = 'admin@mediapager.local'
$env:MEDIAPAGER_SEED_PASS = 'DefaultPasswordChangeMe'
# Optional: replace with your TMDB API key.
# $env:MEDIAPAGER_TMDB_API_KEY = 'PASTE_TMDB_API_KEY_HERE'
```

Alternatively, put the `$env:` assignments in your PowerShell profile (`notepad $PROFILE`).

> **Development only:** without a configured signing key, the launcher uses
> `your_32_byte_sign_key_placeholder_here`. This is public test data; never use it in
> production. SQLite and PostgreSQL hold separate databases; switching or refreshing them
> does not copy accounts, passwords, or saved API keys/settings. Users must create/reset
> accounts and re-enter database-stored API keys in the selected database.

## Build and run locally

Restore and build the .NET solution at the repository root:

```sh
dotnet restore MediaPager.slnx
dotnet build MediaPager.slnx
```

The build also deploys the shipped official plugin assemblies to the current user's
`~/.MediaPager/plugins/official` directory (or the equivalent user-profile location on
Windows). Start the API from the repository root:

```sh
dotnet run --project MediaPager.App.Api/MediaPager.App.Api.csproj
```

The HTTP launch profile uses `http://localhost:5074`; the HTTPS profile also uses
`https://localhost:7069`. Start the UI in another terminal:

```sh
cd MediaPager.App.Ui
npm ci
npm run dev
```

The UI development server uses `http://localhost:5173`. Its development environment
targets the API at `http://localhost:5074`. Set `VITE_API_BASE_URL` to use another API
address. The built SPA can also read `/runtime-config.json` and use its `apiBaseUrl` value
without rebuilding.

On first API startup, MediaPager creates `admin@mediapager.local` as the super-admin if no
super-admin exists and the address is available. A generated temporary password is
printed to the API log once. Change it after signing in. There is no public sign-up; invite
other users from Settings.

Useful component references: [API README](MediaPager.App.Api/README.md) and
[UI README](MediaPager.App.Ui/README.md).

## Environment variables and configuration

This section lists the environment variables used by the application, UI, Docker images,
and supplied Compose file. The app uses normal .NET configuration sources and additionally
loads environment variables with the `MEDIAPAGER_` prefix. For that prefix, `__` means a
nested configuration separator (`MEDIAPAGER_Auth__SeedEmail` becomes `Auth:SeedEmail`). The
prefix is removed before configuration lookup. Other appsettings keys can be overridden
using the same rule; for example, `MEDIAPAGER_AllowedHosts`,
`MEDIAPAGER_Logging__LogLevel__Default`, or a nested plugin-list key. This generic mapping is
also how settings from installed community plugins can be supplied; their setting names
are plugin-defined rather than a fixed application-wide list.

### UI

| Variable | Where it applies | Meaning/default |
|---|---|---|
| `VITE_API_BASE_URL` | UI build time | Used for separate local UI/API development. `.env.development` sets `http://localhost:5074`; the production SPA uses the same-origin `/` base. It is public browser configuration, never a place for credentials. |

At runtime, `/runtime-config.json` with `{ "apiBaseUrl": "https://api.example" }` takes
precedence over the built base URL. If neither is set, the UI uses a same-origin `/` base.

### API database and authentication

| Variable | Purpose, precedence, and default |
|---|---|
| `MEDIAPAGER_Database__Provider` | Database provider: `Sqlite` (default) or `PostgreSQL`. Selects the provider-specific EF migration set. |
| `MEDIAPAGER_ConnectionStrings__AuthDatabase` | Full connection string for the selected provider. SQLite defaults to the platform database path; PostgreSQL requires a connection string. |
| `MEDIAPAGER_DB_PATH` | Legacy SQLite database-path override; takes precedence over the SQLite connection string. Not used for PostgreSQL. |
| `MEDIAPAGER_Auth__SigningKeyPath` | Optional persistent JWT signing-key path; useful when the database is remote. |
| `MEDIAPAGER_SEED_USER` | Initial super-admin email/login. Defaults to `admin@mediapager.local`; used only when the first super-admin is created. |
| `MEDIAPAGER_SEED_PASS` | Optional initial super-admin password. If empty, a temporary password is generated and logged once. |
| `MEDIAPAGER_EKEY` | JWT signing key; must be at least 32 UTF-8 bytes. When omitted, the API generates a random key in persistent app data (beside a SQLite database by default). It is not a database-encryption key. |

SQLite database path resolution starts with `MEDIAPAGER_DB_PATH`, then the configured
connection string/database path, then the platform default. The default is
`%APPDATA%/MediaPager/db/mediapager.db` on Windows and `~/.MediaPager/db/mediapager.db` on
macOS/Linux. PostgreSQL uses the configured connection string. EF applies the selected
provider's migrations at startup. Changing providers creates/updates the schema in that
database; moving existing data between providers is a separate import/export operation.

### Host runtime settings and plugins

| Variable | Configuration key | Purpose/default |
|---|---|---|
| `MEDIAPAGER_Frontend__BaseUrl` | `Frontend:BaseUrl` | Base URL used to create links in email; local default is `http://localhost:5173`. |
| `MEDIAPAGER_Plugins__Directory` | `Plugins:Directory` | Root for `official/` and `community/` plugin folders. Default: `~/.MediaPager/plugins`; Docker sets `/app/plugins`. |
| `MEDIAPAGER_Plugins__Required__Official__<index>` | `Plugins:Required:Official:<index>` | Required/active official plugin ids; use numeric array indexes such as `__0`. |
| `MEDIAPAGER_Plugins__Required__Community__<index>` | `Plugins:Required:Community:<index>` | Required community plugin ids, also using numeric indexes. |
| `MEDIAPAGER_Email__Provider` | `Email:Provider` | Runtime fallback for the selected email provider. |
| `MEDIAPAGER_Subtitles__Provider` | `Subtitles:Provider` | Runtime fallback for the selected subtitle provider. |
| `MEDIAPAGER_Artwork__Directory` | `Artwork:Directory` | Runtime fallback for artwork storage location. |
| `MEDIAPAGER_GIT_SSH_PRIVATE_KEY_PATH` | Direct process environment variable | Path to a mounted private key for installing private plugin repositories. Public HTTPS repositories need no key. SSH-form repo URLs are converted to HTTPS unless this key path is set. |

Runtime selector values are stored in the database when changed in the application; a
stored value takes precedence over its environment/configuration fallback. Keep
`Plugins:Required` in the base appsettings file, not `appsettings.Development.json`, which
loads later and can mask it.

### Plugin setting environment fallbacks

Plugin settings are normally entered in the UI and stored in the application database.
For configuration-based fallback, the setting path is
`plugins.<pluginKey>.<setting>`, so the environment name is
`MEDIAPAGER_plugins__<pluginKey>__<setting>`. A non-empty database setting takes precedence
over this fallback.

| Plugin key | Supported setting names / environment variable forms |
|---|---|
| `tmdb` | `MEDIAPAGER_TMDB_API_KEY`, `MEDIAPAGER_plugins__tmdb__imageBase` |
| `opensubtitles` | `MEDIAPAGER_plugins__opensubtitles__apiKey`, `MEDIAPAGER_plugins__opensubtitles__username`, `MEDIAPAGER_plugins__opensubtitles__password` |
| `subdl` | `MEDIAPAGER_plugins__subdl__apiKey` |
| `smtp` | `MEDIAPAGER_plugins__smtp__host`, `MEDIAPAGER_plugins__smtp__port`, `MEDIAPAGER_plugins__smtp__username`, `MEDIAPAGER_plugins__smtp__password`, `MEDIAPAGER_plugins__smtp__from`, `MEDIAPAGER_plugins__smtp__enableSsl` |
| `mailgun` | `MEDIAPAGER_plugins__mailgun__apiKey`, `MEDIAPAGER_plugins__mailgun__domain`, `MEDIAPAGER_plugins__mailgun__from`, `MEDIAPAGER_plugins__mailgun__apiBaseUrl` |

Community plugins can define their own settings and use the same generic
`MEDIAPAGER_plugins__<pluginKey>__<setting>` configuration fallback. For TMDB, use the
dedicated `MEDIAPAGER_TMDB_API_KEY` variable; a key stored in plugin settings takes
precedence. Do not put secret values
in committed files. Use .NET user-secrets for local development and a deployment secret
store for production.

### Docker, Compose, and framework variables

| Variable | Scope | Purpose/default |
|---|---|---|
| `MEDIAPAGER_IMAGE` | Compose `.env` / shell | Docker Hub image reference; defaults to `mediapager/mediapager:latest`. |
| `MEDIAPAGER_PORT` | Compose `.env` / shell | Host port; defaults to `8080` and maps to the container's port `5000`. |
| `MEDIAPAGER_MEDIA_PATH` | Compose `.env` / shell | Host media directory mounted read-only at `/mnt/media`; defaults to `./media`. |
| `MEDIAPAGER_BASE_URL` | Compose `.env` / shell | Base URL used in email links; defaults to `http://localhost:8080`. |
| `MEDIAPAGER_SEED_USER` | Compose `.env` / shell | Initial admin email/login; defaults to `admin@mediapager.local`. |
| `MEDIAPAGER_SEED_PASS` | Compose `.env` / shell | Optional first-run admin password. |
| `MEDIAPAGER_EKEY` | Compose `.env` / shell | Optional JWT signing key. |
| `MEDIAPAGER_TMDB_API_KEY` | Compose `.env` / shell | Optional TMDB key; saved plugin settings take precedence. |
| `MEDIAPAGER_DATABASE_PROVIDER` | Compose `.env` / shell | Database provider passed to the container; defaults to `Sqlite`. |
| `MEDIAPAGER_AUTH_CONNECTION_STRING` | Compose `.env` / shell | Provider connection string. Compose defaults to its persistent SQLite file; set this with provider `PostgreSQL` to use PostgreSQL. |
| `ASPNETCORE_ENVIRONMENT` | ASP.NET Core host | Launch profiles set `Development`; set an appropriate environment for deployments. |
| `DOTNET_ENVIRONMENT` | .NET host | Standard .NET host environment selector; supported by `WebApplication.CreateBuilder`. |
| `ASPNETCORE_URLS` | ASP.NET Core host/container | Bind address. The image listens on `http://0.0.0.0:5000`; Compose publishes it on `MEDIAPAGER_PORT`. |
| `PLAYWRIGHT_BROWSERS_PATH` | Docker image | Set internally to `/ms-playwright` in build and runtime images; normally leave unchanged. |

The container configures SQLite by default at `/data/db/mediapager-auth.db`, persists its
signing key under `/data`, and sets `MEDIAPAGER_Plugins__Directory=/app/plugins`. To use
PostgreSQL, set `MEDIAPAGER_DATABASE_PROVIDER=PostgreSQL` and
`MEDIAPAGER_AUTH_CONNECTION_STRING` in the Compose `.env` file. Compose creates its own network; no
pre-existing Docker network is required.

## Docker deployment

The Docker Hub image `mediapager/mediapager:latest` contains the API, official plugins,
and production SPA in one container. ASP.NET Core serves the SPA and API from the same
origin. Git and the .NET SDK are included so community plugins can be cloned and built
on demand by the plugin installer.

Clone the deployment files and start MediaPager:

```sh
git clone --depth 1 https://github.com/MediaPager/MediaPager.git
cd MediaPager
docker compose up -d
```

Compose pulls the image, creates its own network and persistent volumes, and publishes the
application at `http://localhost:8080`. No pre-existing network or `.env` file is required.
Container Station and Portainer can deploy the same Compose file as a stack.

### Run the Docker Hub image directly

To start the single container without cloning the repository or using Compose:

```sh
mkdir -p media
docker pull mediapager/mediapager:latest
docker run -d --name mediapager --restart unless-stopped \
  -p 8080:5000 \
  --label com.centurylinklabs.watchtower.enable=true \
  -v mediapager-data:/data \
  -v mediapager-community-plugins:/app/plugins/community \
  -v "$PWD/media:/mnt/media:ro" \
  -e MEDIAPAGER_SEED_USER=admin@mediapager.local \
  -e MEDIAPAGER_Frontend__BaseUrl=http://localhost:8080 \
  mediapager/mediapager:latest
```

Use `/mnt/media/...` paths for catalogs. Get the first-run password with
`docker logs mediapager`. For a custom media directory, change the host path in the bind
mount; for a custom public URL, change `MEDIAPAGER_Frontend__BaseUrl`.

### Mount your media and create catalogs

Compose bind-mounts the host folder in `MEDIAPAGER_MEDIA_PATH` (default `./media`) into the
container at `/mnt/media`, read-only. Put your libraries beneath that folder, for example:

```text
./media/
├── Movies/
└── TV/
```

Then create catalogs in MediaPager using the **container paths** `/mnt/media/Movies` and
`/mnt/media/TV`. Do not enter the host path (such as `/share/Media` or `/Volumes/Media`)
as the catalog path; the API runs inside the container and sees the mounted path instead.

In Container Station or Portainer, bind your host media directory to `/mnt/media` and make
it read-only. For libraries in separate host folders, add a bind mount for each folder at a
distinct container path, then create catalogs using those container paths.

Database/signing-key state and installed community plugins are stored in named Docker
volumes and survive container updates.

On first run, a temporary password for `MEDIAPAGER_SEED_USER` (default
`admin@mediapager.local`) is written to the container log. Get it with:

```sh
docker compose logs mediapager
```

For a local single-architecture build, initialize all submodules and build from the
repository root:

```sh
docker build --build-arg APP_VERSION="$(tr -d '\r\n[:space:]' < VERSION)" \
  -t mediapager/mediapager:latest .
docker compose up --pull never -d
```

### Docker Hub releases

The `.github/workflows/docker-publish.yml` workflow builds and publishes `linux/amd64` and
`linux/arm64` images. It tags each image as `latest`, with the application version from
`VERSION`, with the Git tag, and with the commit SHA.

Stop the deployment with `docker compose down`; named volumes are retained unless removed
explicitly.

## Automatic updates with Watchtower

The MediaPager Compose service already has Watchtower's opt-in label. Install Watchtower as
a separate container on the **same Docker host/endpoint** as MediaPager. This lets it check
Docker Hub hourly and recreate only containers with that label.

### Portainer

1. Select the Portainer environment where the `mediapager` container is running.
2. Open **Stacks → Add stack**, name it `watchtower`, and choose **Web editor**.
3. Paste and deploy this Compose definition:

```yaml
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: ["--label-enable", "--interval", "3600", "--cleanup"]
```

### NAS Container Station / Container Manager

Create a Watchtower application/stack using the same YAML above. Ensure its volume maps the
NAS Docker socket at `/var/run/docker.sock` to that same path in the container. The MediaPager
service's `com.centurylinklabs.watchtower.enable=true` label is already in this repository's
Compose file, so no label changes are needed when deploying it from here.

After deployment, Watchtower checks for a newer `latest` image every hour, then recreates
MediaPager. The database and community-plugin volumes are retained. The Docker socket grants
Watchtower control of the Docker host, so only run it on a trusted NAS/Portainer endpoint.

**Maintenance note:** the upstream `containrrr/watchtower` repository is archived. This
guide describes its current usage; consider that status when choosing unattended updates.

## Plugin development and discovery

### Repository and manifest conventions

Plugin repositories use the name `MediaPager.Plugins.<Type>.<Name>`, with a known plugin
type such as `Stream`, `Search`, `Metadata`, `Subtitles`, `Email`, `Actions`, or `Interface`.
Each plugin repository includes a root manifest named
`MediaPager.Plugins.<Type>.<Name>.manifest.json`. The manifest declares its plugin id,
display name, description, author, capabilities, SDK, and SDK major version. Optional
fields can declare dependencies and whether a plugin appears in Community discovery.

Buildable plugins should reference `MediaPager.App.PluginContracts`, not the API or Core.
The manifest and repo name are checked during discovery and installation; installation
also checks the manifest against the built plugin. Community plugins should target the
host SDK major version.

### Community discovery and install

The Community tab searches public GitHub repositories by the plugin naming convention and
requires a valid repo-root manifest. Discovery only reads repository metadata and the
manifest; it does not clone or execute code. The official `MediaPager` organization is
excluded from Community search because its projects belong in the API's official catalog.

Installing a listed community plugin clones the selected repository/branch, validates the
manifest, publishes the project on the server, verifies the output, and loads it from the
community directory. Public HTTPS repositories work without credentials. For a private
repository, mount a deploy key and set `MEDIAPAGER_GIT_SSH_PRIVATE_KEY_PATH` in the API
process environment. Secret key material must not be included in the image or source repo.

## Data, accounts, and operations

- The selected auth database (SQLite by default or PostgreSQL), runtime settings, accounts,
  and plugin settings are stored together in that database. Back up the database and
  `signing.key` as sensitive operational data.
- The API creates the first super-admin only when no super-admin exists and the configured
  seed email is unused. A blank `Auth:SeedPassword` generates a temporary password that is
  written to the startup log. Change it on first login.
- Registration is invitation-based; use Settings to invite additional accounts.
- Configure provider credentials from Settings → Plugins or Settings → Email. Secret
  fields are not returned in settings responses; submitting a blank secret keeps the
  current value.
- Keep production credentials out of `appsettings*.json`, `.env.example`, source control,
  container images, and logs. Use .NET user-secrets locally or the host/orchestrator's
  secret mechanism in production.

For a local signing key, from the superproject root:

```sh
dotnet user-secrets set "Auth:SigningKey" "$(openssl rand -base64 48)" \
  --project MediaPager.App.Api/MediaPager.App.Api.csproj
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Project files are missing or `dotnet build` cannot resolve a project reference | Run `git submodule update --init --recursive` and build from the superproject root. |
| UI cannot reach the API | Confirm the API is listening on port 5074; check `VITE_API_BASE_URL` or the runtime `runtime-config.json`. |
| Docker Compose reports an unavailable image | Run `docker compose pull`; check that Docker Hub has `mediapager/mediapager:latest`. |
| Port `8080` is already in use | Set `MEDIAPAGER_PORT` in `.env` to another free host port. |
| UI or API does not start | Check `docker compose logs mediapager`; both run in the same container. |
| Plugin install fails for a public repository | Confirm the repository name, default/selected branch, root manifest filename, and SDK major version. |
| Private plugin clone fails | Mount a valid deploy key and set `MEDIAPAGER_GIT_SSH_PRIVATE_KEY_PATH`; public repositories need no SSH configuration. |
| Email or provider requests fail | Confirm that provider settings are configured in the UI and that the plugin is enabled/loaded. |

For component-specific details, see the API and UI READMEs linked above.
