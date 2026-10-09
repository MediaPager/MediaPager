# MediaPager

<p align="center">
	<img src="https://github.com/nobugsgiven/dev.nobugsgiven.apps.MediaPager.App.Ui/blob/master/src/assets/images/icon.png?raw=true" alt="MediaPager play icon" width="160"><br>
	<span style="font-family: 'JetBrains Mono', monospace; font-size: 28px; font-weight: 700;">mediapager<span style="color: #86d411;">_</span></span>
</p>

MediaPager is a modular, **plugin-driven media platform**: an ASP.NET Core (.NET 10) API
host, a Vue 3 + Quasar single-page app, and a plugin SDK that every capability — metadata,
search, stream, subtitles, actions — is built behind. This repository is the **superproject**: it
tracks orchestration/config plus one git submodule per component. Each component is its own
repo under `nobugsgiven`, named `dev.nobugsgiven.apps.MediaPager.<Component>`.

## Components

| Path | Repo | What it is |
|---|---|---|
| `MediaPager.App.Api` | `dev.nobugsgiven.apps.MediaPager.App.Api` | The web host: config, DI, auth/JWT, migrations + seeds, plugin loading, controllers. |
| `MediaPager.App.Core` | `dev.nobugsgiven.apps.MediaPager.App.Core` | Host-side domain: EF entities + `AuthDbContext`, migrations, settings stores, plugin host. |
| `MediaPager.App.PluginContracts` | `dev.nobugsgiven.apps.MediaPager.App.PluginContracts` | The **plugin SDK** — interfaces + DTOs only, zero dependencies. |
| `MediaPager.Plugins.Search.Tmdb` | `dev.nobugsgiven.apps.MediaPager.Plugins.Search.Tmdb` | Official TMDB metadata + search provider. |
| `MediaPager.Plugins.Subtitles.OpenSubtitles` | `dev.nobugsgiven.apps.MediaPager.Plugins.Subtitles.OpenSubtitles` | Official OpenSubtitles subtitle provider. |
| `MediaPager.Plugins.Subtitles.Subdl` | `dev.nobugsgiven.apps.MediaPager.Plugins.Subtitles.Subdl` | Official Subdl subtitle provider. |
| `MediaPager.App.Ui` | `dev.nobugsgiven.apps.MediaPager.App.Ui` | The Vue 3 + Quasar SPA. |

## Plugin architecture

Everything is a **provider**, surfaced through one registry:

- Plugins reference **Contracts by default** — a clean, dependency-free seam. A single plugin
  class implements any mix of provider contracts, generic actions, activity, and navigation.
  Optional community inter-plugin contracts stay in separate repositories.
- Manifests may require other plugin ids; `IPluginHost` exposes loaded plugin instances to
  plugins without coupling Core/API to their optional capabilities.
- The **Core** owns the domain (never referenced by plugins); the **Api** hosts Core and the
  plugin registry.
- Plugin settings are core-hosted under `plugins.<pluginKey>.<name>` and drive a data-driven
  settings UI in the SPA — no per-provider hard-coding.
- The SPA is `/sources`-driven: nav, browse/details screens, and settings render generically
  from whatever plugins are loaded; custom provider UIs run in sandboxed iframes bridged over
  `postMessage` (the token never crosses).

Official plugins ship in the image. Community/out-of-tree plugins install through the deployer
(clone → validate manifest → compile → load) and remain independent of host-specific services.

## Clone

Components are git submodules, so fetch them too:

```sh
git clone --recurse-submodules git@github.com:nobugsgiven/dev.nobugsgiven.apps.MediaPager.git
# or, in an existing clone:
git submodule update --init --recursive
```

## Requirements

- .NET 10 SDK
- Node.js and npm

TMDB, OpenSubtitles/Subdl, and Mailgun credentials enable their respective metadata,
subtitle, and email features (configured in the app under **Settings**, or via
`MPAGER_`-prefixed environment variables).

## Run locally

Start the API in one terminal:

```sh
dotnet run --project MediaPager.App.Api/MediaPager.App.Api.csproj    # http://localhost:5074
```

Start the SPA in another:

```sh
cd MediaPager.App.Ui
npm install
npm run dev                                                  # http://localhost:5173
```

Sign in with the seeded super-admin (`admin@mediapager.local`); a temporary password is
printed once in the API startup log on first run. See `MediaPager.App.Api/README.md` and
`MediaPager.App.Ui/README.md` for details.
