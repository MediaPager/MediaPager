# MediaPager

<p align="center">
  <img src="https://github.com/MediaPager/MediaPager.App.Ui/blob/master/src/assets/images/icon.png?raw=true" alt="MediaPager play icon" width="160"><br>
  <strong>Self-hosted media, built to be extended</strong>
</p>

MediaPager is a self-hosted media platform composed of an ASP.NET Core API, a Vue 3 +
Quasar web app, a plugin SDK, and independently versioned plugins. Search, metadata,
playback, subtitles, email, and other capabilities are provided through plugins instead
of being hard-wired to one provider.

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
| `VITE_API_BASE_URL` | UI build time | API base URL embedded by Vite. `.env.development` sets `http://localhost:5074`; `.env`/`.env.production` use `/`. It is public browser configuration, never a place for credentials. |

At runtime, `/runtime-config.json` with `{ "apiBaseUrl": "https://api.example" }` takes
precedence over the built base URL. If neither is set, the UI uses a same-origin `/` base.

### API database and authentication

| Variable | Purpose, precedence, and default |
|---|---|
| `MEDIAPAGER_DB_PATH` | Direct database-path override; checked first. |
| `MEDIAPAGER_SEED_USER` | Initial super-admin email/login. Defaults to `admin@mediapager.local`; used only when the first super-admin is created. |
| `MEDIAPAGER_SEED_PASS` | Optional initial super-admin password. If empty, a temporary password is generated and logged once. |
| `MEDIAPAGER_EKEY` | JWT signing key; must be at least 32 UTF-8 bytes. When omitted, the API generates a random key and stores it as `signing.key` beside the database. It is not a database-encryption key. |

Database path resolution starts with `MEDIAPAGER_DB_PATH`, then configured database
settings/connection strings, then the platform default. The
default is `%APPDATA%/MediaPager/db/mediapager.db` on Windows and
`~/.MediaPager/db/mediapager.db` on macOS/Linux. Any path is normalized to an absolute path
at startup. These defaults use the operating system user profile (`APPDATA` on Windows;
`HOME`/the user profile on macOS and Linux); set one of the database-path variables to
avoid relying on the service account's home directory.

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
| `MEDIAPAGER_QNET_NETWORK` | Compose `.env` / shell | Required name of the pre-existing QNAP `qnet` network. |
| `MEDIAPAGER_WEB_IP` | Compose `.env` / shell | Required unused LAN IP assigned to the web container. |
| `MEDIAPAGER_DATA_DIR` | Compose `.env` / shell | Required host directory mounted at `/data` for persistent database and application state. |
| `MEDIAPAGER_MOVIES_DIR` | Compose `.env` / shell | Required host media directory mounted at `/mnt/movies`; the current app does not yet use this mount. |
| `MEDIAPAGER_SEED_USER` | Compose `.env` / shell | Initial admin email/login, passed directly to the API. |
| `MEDIAPAGER_SEED_PASS` | Compose `.env` / shell | Optional first-run admin password. |
| `MEDIAPAGER_EKEY` | Compose `.env` / shell | Optional JWT signing key. |
| `MEDIAPAGER_TMDB_API_KEY` | Compose `.env` / shell | Optional TMDB key; saved plugin settings take precedence. |
| `ASPNETCORE_ENVIRONMENT` | ASP.NET Core host | Launch profiles set `Development`; set an appropriate environment for deployments. |
| `DOTNET_ENVIRONMENT` | .NET host | Standard .NET host environment selector; supported by `WebApplication.CreateBuilder`. |
| `ASPNETCORE_URLS` | ASP.NET Core host/container | API bind addresses. Docker sets `http://0.0.0.0:5000`; local launch profiles configure their own URLs. |
| `PLAYWRIGHT_BROWSERS_PATH` | Docker image | Set internally to `/ms-playwright` in build and runtime images; normally leave unchanged. |
| `DOCKER_CONFIG` | Optional external Docker/Watchtower tooling | Example in `.env.example`; not consumed by the app or current Compose services. |
| `WATCHTOWER_POLL_INTERVAL` | Optional external Watchtower tooling | Example in `.env.example`; only relevant if Watchtower is deployed separately. |

The API Docker image also sets `MEDIAPAGER_DB_PATH=/data/db/mediapager-auth.db` and
`MEDIAPAGER_Plugins__Directory=/app/plugins`. The Compose `.env` variables for network, IP,
and host paths are used by Compose interpolation; they are not automatically passed to
the API container unless `docker-compose.yml` maps them under `environment:`.

## Docker deployment

Build both images from the repository root after initializing all submodules:

```sh
docker build -f Dockerfile.api -t mediapager-api:latest .
docker build -f Dockerfile.web -t mediapager-web:latest .
```

`Dockerfile.api` publishes the API and its referenced official plugins, installs the
Playwright Chromium runtime dependencies, and stores application state under `/data`.
`Dockerfile.web` builds the SPA and serves it through nginx, proxying API requests to
`mediapager-api:5000` on the internal Docker network.

The provided Compose deployment uses those local image tags. Prepare the host settings:

```sh
cp .env.example .env
# Edit .env: set the qnet name, free web IP, persistent data path, and media path.
# MEDIAPAGER_SEED_USER optionally changes the initial admin email.
docker compose up -d
docker compose logs -f mediapager-api
```

This Compose file requires a pre-existing QNAP `qnet` network. The web service is assigned
the configured LAN address on port 80; the API has no published host port and is reached
through the internal network. Persist `/data` and protect its database and signing key.
For another Docker network or a generic host deployment, provide an equivalent deployment
override rather than assuming the QNAP network exists.

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

- The SQLite auth database, runtime settings, accounts, and plugin settings are kept
  together under the configured data path. Back up the database and `signing.key` as
  sensitive operational data.
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
| Docker Compose reports a missing variable | Copy `.env.example` to `.env` and fill in the required qnet name, web IP, data path, and media path. |
| Docker Compose cannot find `qnet` | Set `MEDIAPAGER_QNET_NETWORK` to an existing QNAP `qnet` network name. |
| The web container cannot reach the API | Keep both services on the internal network and use the Compose service name `mediapager-api`. |
| Plugin install fails for a public repository | Confirm the repository name, default/selected branch, root manifest filename, and SDK major version. |
| Private plugin clone fails | Mount a valid deploy key and set `MEDIAPAGER_GIT_SSH_PRIVATE_KEY_PATH`; public repositories need no SSH configuration. |
| Email or provider requests fail | Confirm that provider settings are configured in the UI and that the plugin is enabled/loaded. |

For component-specific details, see the API and UI READMEs linked above.
