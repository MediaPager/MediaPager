# MediaPager

MediaPager is a self-hosted media library and playback app. It combines an ASP.NET Core API,
a Vue/Quasar web app, and a plugin system for search, metadata, playback, subtitles, email, and
other integrations.

## Get started

For the supported container setup, follow **[INSTALL_DOCKER.md](INSTALL_DOCKER.md)**. The
step-by-step **[Portainer Stack guide](PORTAINER.md)** covers both the default SQLite Compose
stack and the PostgreSQL stack. Both use persistent application data on `/data`; switching
between database variants does not migrate data.

First login creates the configured seed super-admin when the selected database has no
super-admin. The temporary password is printed in the API log. There is no open registration;
administrators invite additional users from Settings.

## Storage at a glance

MediaPager-managed files (database, local artwork, tools, plugin installs, and runtime config)
belong under the persistent application data root. Large movie, TV, and other catalog media is
user-managed: each catalog points to its own folder. A separate host or NAS mount is recommended
so other apps can access the media independently of MediaPager. For CIFS/SMB ownership and write
permissions, see the [Docker media-storage notes](INSTALL_DOCKER.md#nas-and-cifssmb-shares).

## Project and development

This repository is the superproject; the API, Core, UI, plugin SDK, and official plugins are
separately maintained repositories checked out as submodules. Clone with:

```sh
git clone --recurse-submodules https://github.com/MediaPager/MediaPager.git
```

For local development, install Git, the .NET 10 SDK, Node.js 24/npm, and Docker, then run:

```sh
./dev.sh up
```

The launcher starts the SQLite and PostgreSQL development instances and the Vue development
server. Use `./dev.sh help` for the available commands. Component-specific details live in each
component repository’s README; plugin authors should start with
[`MediaPager.App.PluginContracts/README.md`](MediaPager.App.PluginContracts/README.md).

More complete hosted documentation is planned for a future documentation site.
