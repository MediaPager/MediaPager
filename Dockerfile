# ---------- Build SPA ----------
FROM node:24-trixie AS ui-build
WORKDIR /src/MediaPager.App.Ui
COPY NoBugsGiven.Quasar.Interop/packages/vue /src/NoBugsGiven.Quasar.Interop/packages/vue
COPY MediaPager.App.Ui/ ./
RUN npm ci && npm run build

# ---------- Build API and official plugins ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS app-build
WORKDIR /src
ARG APP_VERSION=0.0.0-dev
COPY MediaPager.App.Api ./MediaPager.App.Api
COPY MediaPager.App.Core ./MediaPager.App.Core
COPY MediaPager.App.PluginContracts ./MediaPager.App.PluginContracts
COPY MediaPager.Plugins.Metadata.MusicBrainz ./MediaPager.Plugins.Metadata.MusicBrainz
COPY NoBugsGiven.Quasar.Interop ./NoBugsGiven.Quasar.Interop
COPY MediaPager.Plugins.Email.MailGun ./MediaPager.Plugins.Email.MailGun
COPY MediaPager.Plugins.Email.Smtp ./MediaPager.Plugins.Email.Smtp
COPY MediaPager.Plugins.Search.Local ./MediaPager.Plugins.Search.Local
COPY MediaPager.Plugins.Search.Tmdb ./MediaPager.Plugins.Search.Tmdb
COPY MediaPager.Plugins.Stream.Local ./MediaPager.Plugins.Stream.Local
COPY MediaPager.Plugins.Subtitles.OpenSubtitles ./MediaPager.Plugins.Subtitles.OpenSubtitles
COPY MediaPager.Plugins.Subtitles.Subdl ./MediaPager.Plugins.Subtitles.Subdl

# Publish the API and deploy shipped official plugins into its plugin directory.
RUN dotnet publish MediaPager.App.Api/MediaPager.App.Api.csproj -c Release -o /app/publish \
    -p:CompressionEnabled=false \
    -p:Version=${APP_VERSION} \
    -p:MediaPagerOfficialPluginsDir=/app/publish/plugins/official

# The SPA and API share one origin in the single-container deployment.
COPY --from=ui-build /src/MediaPager.App.Ui/dist/ /app/publish/wwwroot/
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

# ---------- Runtime ----------
# Community plugin builds use the pinned SDK stored in the persistent tools volume; the
# application image needs only the ASP.NET runtime and Git.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS runtime
WORKDIR /app
ARG APP_VERSION=0.0.0-dev
LABEL org.opencontainers.image.title="MediaPager" \
    org.opencontainers.image.source="https://github.com/MediaPager/MediaPager" \
    org.opencontainers.image.version=${APP_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git openssh-client fonts-liberation libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
    libcairo2 libcups2t64 libdbus-1-3 libdrm2 libexpat1 libgbm1 libglib2.0-0t64 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
    libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxrandr2 \
    libxrender1 libxss1 libxtst6 wget \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=10001:10001 --from=app-build /app/publish .
COPY --from=app-build /app/docker-entrypoint.sh /app/docker-entrypoint.sh

# Keep the SQLite default in the provider connection string, not the SQLite-only legacy path
# variable, so PostgreSQL deployments can select their provider without inheriting DB_PATH.
ENV ASPNETCORE_URLS=http://0.0.0.0:5000 \
    MEDIAPAGER_ConnectionStrings__AuthDatabase="Data Source=/data/db/mediapager-auth.db" \
    MEDIAPAGER_Plugins__Directory=/app/plugins
RUN groupadd --system --gid 10001 mediapager \
    && useradd --system --uid 10001 --gid 10001 --home-dir /home/mediapager \
       --create-home --shell /usr/sbin/nologin mediapager \
    && mkdir -p /data /tools /app/plugins/community \
    && chmod 0755 /app/docker-entrypoint.sh \
    && chown -R mediapager:mediapager /data /tools /home/mediapager /app/plugins/community

EXPOSE 5000
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["MediaPager.App.Api.dll"]
