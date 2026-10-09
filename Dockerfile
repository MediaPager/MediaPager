# ---------- Build SPA ----------
FROM node:24-trixie AS ui-build
WORKDIR /src/MediaPager.App.Ui
COPY MediaPager.App.Ui/ ./
RUN npm ci && npm run build

# ---------- Build API and official plugins ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS app-build
WORKDIR /src
ARG APP_VERSION=dev
COPY MediaPager.App.Api ./MediaPager.App.Api
COPY MediaPager.App.Core ./MediaPager.App.Core
COPY MediaPager.App.PluginContracts ./MediaPager.App.PluginContracts
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

# Install Playwright Chromium and its OS dependencies for server-side browser tasks.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g playwright@1.63.0 \
    && playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*

# ---------- Runtime ----------
# Community plugin installs clone and compile plugins inside the application container,
# so the runtime image includes the .NET SDK and Git as well as the ASP.NET runtime.
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS runtime
WORKDIR /app
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="MediaPager" \
    org.opencontainers.image.source="https://github.com/MediaPager/MediaPager" \
    org.opencontainers.image.version=${APP_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates ffmpeg git openssh-client fonts-liberation libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
    libcairo2 libcups2t64 libdbus-1-3 libdrm2 libexpat1 libgbm1 libglib2.0-0t64 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
    libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxrandr2 \
    libxrender1 libxss1 libxtst6 wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=app-build /app/publish .

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    ASPNETCORE_URLS=http://0.0.0.0:5000 \
    MEDIAPAGER_DB_PATH=/data/db/mediapager-auth.db \
    MEDIAPAGER_Plugins__Directory=/app/plugins
COPY --from=app-build /ms-playwright /ms-playwright

EXPOSE 5000
ENTRYPOINT ["dotnet", "MediaPager.App.Api.dll"]
