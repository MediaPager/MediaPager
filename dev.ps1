param([string]$Command = 'help')

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$ApiPort = 5074
$SpaPort = 5173
$PostgresApiPort = 5075
$PostgresSpaPort = 5174
$RunDir = Join-Path $HOME '.MediaPager\dev'
$CredentialFile = Join-Path $RunDir 'credentials.ps1'
$ApiPidFile = Join-Path $RunDir 'api.pid'
$SpaPidFile = Join-Path $RunDir 'spa.pid'
$PostgresApiPidFile = Join-Path $RunDir 'postgres-api.pid'
$PostgresSpaPidFile = Join-Path $RunDir 'postgres-spa.pid'
$ApiLog = Join-Path $RunDir 'api.log'
$SpaLog = Join-Path $RunDir 'spa.log'
$PostgresApiLog = Join-Path $RunDir 'postgres-api.log'
$PostgresSpaLog = Join-Path $RunDir 'postgres-spa.log'
$PostgresPublishLog = Join-Path $RunDir 'postgres-publish.log'
$PostgresDropLog = Join-Path $RunDir 'postgres-drop.log'
$RefreshBuildLog = Join-Path $RunDir 'refresh-build.log'
$NpmInstallLog = Join-Path $RunDir 'npm-install.log'
$PostgresPluginDir = Join-Path $RunDir 'postgres-plugins'
$PostgresAppDir = Join-Path $RunDir 'postgres-app'
$PostgresContainer = 'postgis'
$PostgresImage = 'imresamu/postgis:18-3.6'
$PostgresVolume = 'mediapager-dev-postgis-data'
$PostgresDefaultConnectionString = 'Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password'
$DefaultDevSigningKey = 'your_32_byte_sign_key_placeholder_here'

# Seed values can be set in the parent shell/profile or this local credentials script.
if (Test-Path -LiteralPath $CredentialFile) {
    . $CredentialFile
}

$DbFile = $env:MEDIAPAGER_DB_PATH
if ([string]::IsNullOrWhiteSpace($DbFile)) {
    $AppDataRoot = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $AppDataRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
    }
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $AppDataRoot = Join-Path $HOME 'AppData\Roaming'
    }
    $DbFile = Join-Path $AppDataRoot 'MediaPager\db\mediapager.db'
}
if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_Auth__SigningKey)) {
    if (-not [string]::IsNullOrWhiteSpace($env:MEDIAPAGER_EKEY)) {
        $env:MEDIAPAGER_Auth__SigningKey = $env:MEDIAPAGER_EKEY
    }
    else {
        $env:MEDIAPAGER_Auth__SigningKey = $DefaultDevSigningKey
    }
}
$env:MEDIAPAGER_EKEY = $env:MEDIAPAGER_Auth__SigningKey
$UsingDefaultDevSigningKey = $env:MEDIAPAGER_Auth__SigningKey -eq $DefaultDevSigningKey
if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_SEED_USER)) {
    $env:MEDIAPAGER_SEED_USER = 'admin@mediapager.local'
}
if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_SEED_PASS)) {
    $env:MEDIAPAGER_SEED_PASS = 'DefaultPasswordChangeMe'
}
$UsingDefaultPostgresSettings = $false
if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_Database__Provider)) {
    $UsingDefaultPostgresSettings = $true
    $env:MEDIAPAGER_Database__Provider = 'PostgreSQL'
}
if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_ConnectionStrings__AuthDatabase)) {
    $UsingDefaultPostgresSettings = $true
    $env:MEDIAPAGER_ConnectionStrings__AuthDatabase = $PostgresDefaultConnectionString
}
$PostgresConnectionString = $env:MEDIAPAGER_ConnectionStrings__AuthDatabase
$UseLocalPostgresContainer = $PostgresConnectionString -eq $PostgresDefaultConnectionString

$PluginRoot = $env:MEDIAPAGER_Plugins__Directory
if ([string]::IsNullOrWhiteSpace($PluginRoot)) {
    $PluginRoot = Join-Path $HOME '.MediaPager\plugins'
}

function Write-Usage {
    @"
MediaPager Windows dev environment

  SQLite     API http://localhost:$ApiPort | SPA http://localhost:$SpaPort
  PostgreSQL API http://localhost:$PostgresApiPort | SPA http://localhost:$PostgresSpaPort

  .\dev.ps1 up          start both API/SPA pairs
  .\dev.ps1 down        stop both pairs (leaves your PostgreSQL server running)
  .\dev.ps1 restart     down, then up
  .\dev.ps1 show        show URLs and service states
  .\dev.ps1 secrets     show configured variable names/status (not secret values)
  .\dev.ps1 --refresh   drop both dev databases, then migrate + seed them from scratch
  .\dev.ps1 help        print this help; no argument also prints help

Environment variables are read from the current shell. If PostgreSQL settings are missing,
the script uses the local PostGIS defaults. Optional local-only overrides:
  $CredentialFile

  Missing PostgreSQL settings default to local PostGIS (postgres/password, database mediapager_dev).
  The PostGIS container stays running when the dev APIs are stopped.
Logs: $RunDir
"@ | Write-Host
}

function ConvertTo-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [object[]]$Arguments = @(),
        [string]$LogFile,
        [switch]$Append
    )
    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($PSBoundParameters.ContainsKey('LogFile')) {
            if ($Append) { & $FilePath @Arguments *>> $LogFile }
            else { & $FilePath @Arguments *> $LogFile }
        }
        else {
            & $FilePath @Arguments
        }
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }
}

function Get-PortProcessIds([int]$Port) {
    try {
        return @(
            Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
                Select-Object -ExpandProperty OwningProcess -Unique
        )
    }
    catch {
        return @()
    }
}

function Test-Port([int]$Port) {
    return (@(Get-PortProcessIds $Port).Count -gt 0)
}

function Write-ErrorLog([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $Matches = @(Select-String -Path $Path -Pattern '(?i)error|exception|fatal|failed|failure|fail:|unhandled|cannot|could not|does not exist|not found|deps\.json|MSB\d+' | Select-Object -Last 20)
    if ($Matches.Count -gt 0) {
        $Matches | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
    }
    else {
        Write-Host "No matching error lines were recognized; full log: $Path" -ForegroundColor Yellow
    }
}

function Ensure-Postgres {
    if (-not $UseLocalPostgresContainer) {
        Write-Host '-> checking configured PostgreSQL connection'
        return
    }
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
        throw 'Docker Desktop is required for the default local PostGIS database. Install Docker or configure MEDIAPAGER_ConnectionStrings__AuthDatabase.'
    }
    if ((Invoke-NativeCommand 'docker.exe' @('info') $null) -ne 0) { throw 'Docker is installed but not running. Start Docker Desktop and retry.' }

    if ((Invoke-NativeCommand 'docker.exe' @('container', 'inspect', $PostgresContainer) $null) -eq 0) {
        $IsRunning = (& docker.exe inspect --format '{{.State.Running}}' $PostgresContainer).Trim()
        if ($IsRunning -ne 'true') {
            Write-Host '-> starting local PostGIS container'
            if ((Invoke-NativeCommand 'docker.exe' @('start', $PostgresContainer) $null) -ne 0) { throw "Could not start container $PostgresContainer." }
        }
    }
    else {
        if (Test-Port 5432) {
            throw 'Port 5432 is in use but the postgis container does not exist. Free the port or configure a different PostgreSQL connection.'
        }
        if ((Invoke-NativeCommand 'docker.exe' @('volume', 'inspect', $PostgresVolume) $null) -ne 0) {
            if ((Invoke-NativeCommand 'docker.exe' @('volume', 'create', $PostgresVolume) $null) -ne 0) { throw "Could not create Docker volume $PostgresVolume." }
        }
        Write-Host '-> creating local PostGIS container'
        $RunArguments = @(
            'run', '-d', '--name', $PostgresContainer,
            '-e', 'POSTGRES_PASSWORD=password',
            '-p', '5432:5432',
            '-v', "${PostgresVolume}:/var/lib/postgresql",
            $PostgresImage
        )
        if ((Invoke-NativeCommand 'docker.exe' $RunArguments $null) -ne 0) { throw 'Could not start the local PostGIS container.' }
    }

    Write-Host '-> waiting for local PostGIS'
    for ($Attempt = 0; $Attempt -lt 90; $Attempt++) {
        if ((Invoke-NativeCommand 'docker.exe' @('exec', $PostgresContainer, 'pg_isready', '-U', 'postgres', '-d', 'postgres') $null) -eq 0) {
            Write-Host '-> local PostGIS is ready'
            return
        }
        Start-Sleep -Seconds 1
    }
    $PostgresContainerLog = Join-Path $RunDir 'postgis.log'
    $null = Invoke-NativeCommand 'docker.exe' @('logs', '--tail', '100', $PostgresContainer) $PostgresContainerLog
    Write-Host 'ERROR: local PostGIS failed readiness check.' -ForegroundColor Red
    Write-ErrorLog $PostgresContainerLog
    throw 'Local PostGIS did not become ready.'
}

function Ensure-UiDependencies {
    $UiDirectory = Join-Path $RepoRoot 'MediaPager.App.Ui'
    $ViteBin = Join-Path $UiDirectory 'node_modules\.bin\vite.cmd'
    if (Test-Path -LiteralPath $ViteBin) { return }
    Write-Host '-> installing SPA dependencies'
    Push-Location $UiDirectory
    try {
        $InstallExitCode = Invoke-NativeCommand 'npm.cmd' @('ci') $NpmInstallLog
        if ($InstallExitCode -ne 0) {
            Write-Host 'ERROR: npm ci failed.' -ForegroundColor Red
            Write-ErrorLog $NpmInstallLog
            throw 'npm ci failed.'
        }
    }
    finally {
        Pop-Location
    }
}

function Warn-OptionalSetup {
    if ([string]::IsNullOrWhiteSpace($env:MEDIAPAGER_TMDB_API_KEY)) {
        Write-Host '!! TMDB API key is not set; optional metadata/search features need a key.' -ForegroundColor Yellow
        Write-Host "   Create a TMDB account, request an API key, then set MEDIAPAGER_TMDB_API_KEY in $CredentialFile."
    }
}

function Write-DevelopmentNotice {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host 'Your MediaPager dev environment is UP' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Cyan
    $SeedUserDisplay = $env:MEDIAPAGER_SEED_USER
    $SeedPasswordDisplay = $env:MEDIAPAGER_SEED_PASS
    if ($env:MEDIAPAGER_SEED_PASS -eq 'DefaultPasswordChangeMe') {
        $SeedPasswordNote = 'DefaultPasswordChangeMe is used for a fresh DB or after --refresh.'
    }
    else {
        $SeedPasswordNote = 'Custom MEDIAPAGER_SEED_PASS override; used only when creating a new admin.'
    }
    Write-Host ''
    Write-Host 'PostgreSQL' -ForegroundColor DarkYellow
    Write-Host "  Site: http://localhost:$PostgresSpaPort  <- use this to access the app" -ForegroundColor Green
    Write-Host "  API:  http://localhost:$PostgresApiPort"
    Write-Host "  User: $SeedUserDisplay"
    Write-Host "  Pass: $SeedPasswordDisplay"
    Write-Host "  Note: $SeedPasswordNote" -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'SQLite' -ForegroundColor DarkYellow
    Write-Host "  Site: http://localhost:$SpaPort  <- use this to access the app" -ForegroundColor Green
    Write-Host "  API:  http://localhost:$ApiPort"
    Write-Host "  User: $SeedUserDisplay"
    Write-Host "  Pass: $SeedPasswordDisplay"
    Write-Host "  Note: $SeedPasswordNote" -ForegroundColor Yellow
    Write-Host '  Seed credentials are used only for an empty DB; existing account passwords are unchanged.'
    if ($UsingDefaultDevSigningKey) {
        Write-Host "!! Using the standard development signing key: $DefaultDevSigningKey" -ForegroundColor Yellow
        Write-Host '   This key is public test data. Never use it for production.' -ForegroundColor Yellow
    }
    Write-Host '   Changing or refreshing databases does not copy users or saved API keys/settings.'
    Write-Host '   Users must create/reset accounts and re-enter database-stored API keys in the new database.'
    Write-Host ''
    Write-Host ''
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host 'Optional persistent settings' -ForegroundColor Green
    Write-Host "Copy these defaults into $CredentialFile to save them between sessions:"
    Write-Host ''
$PowerShellSettings = @'
  $env:MEDIAPAGER_Database__Provider = 'PostgreSQL'
  $env:MEDIAPAGER_ConnectionStrings__AuthDatabase = 'Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password'
  $env:MEDIAPAGER_Auth__SigningKey = 'your_32_byte_sign_key_placeholder_here'
  $env:MEDIAPAGER_DB_PATH = (Join-Path $HOME 'AppData\Roaming\MediaPager\db\mediapager.db')
  $env:MEDIAPAGER_SEED_USER = 'admin@mediapager.local'
  $env:MEDIAPAGER_SEED_PASS = 'DefaultPasswordChangeMe'
  # Optional: create a TMDB account, request an API key, and replace this value.
  # $env:MEDIAPAGER_TMDB_API_KEY = 'PASTE_TMDB_API_KEY_HERE'
'@
    Write-Host $PowerShellSettings
    Write-Host '  To persist these in your PowerShell profile instead: notepad $PROFILE'
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
}

function Get-RecordedProcess([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $Parts = (Get-Content -LiteralPath $Path -Raw).Trim() -split '\s+'
    if ($Parts.Count -lt 2) { return $null }
    $ProcessId = 0
    $StartTicks = 0L
    if (-not [int]::TryParse($Parts[0], [ref]$ProcessId)) { return $null }
    if (-not [long]::TryParse($Parts[1], [ref]$StartTicks)) { return $null }
    $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $Process) { return $null }
    try {
        if ($Process.StartTime.Ticks -ne $StartTicks) { return $null }
    }
    catch {
        return $null
    }
    return $Process
}

function Test-ProcessIdFile([string]$Path) {
    return [bool](Get-RecordedProcess $Path)
}

function Stop-ServicePair([string]$Name, [string]$PidFile, [int]$Port) {
    $HadService = $false
    if (Test-Path -LiteralPath $PidFile) {
        $Process = Get-RecordedProcess $PidFile
        if ($Process) {
            $HadService = $true
            Write-Host "-> stopping $Name (pid $($Process.Id))"
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }

    foreach ($ListenerId in @(Get-PortProcessIds $Port)) {
        $HadService = $true
        Write-Host "-> stopping listener on :$Port (pid $ListenerId)"
        Stop-Process -Id $ListenerId -Force -ErrorAction SilentlyContinue
    }
    return $HadService
}

function Stop-Environment {
    $HadService = $false
    if (Stop-ServicePair 'SQLite API' $ApiPidFile $ApiPort) { $HadService = $true }
    if (Stop-ServicePair 'SQLite SPA' $SpaPidFile $SpaPort) { $HadService = $true }
    if (Stop-ServicePair 'PostgreSQL API' $PostgresApiPidFile $PostgresApiPort) { $HadService = $true }
    if (Stop-ServicePair 'PostgreSQL SPA' $PostgresSpaPidFile $PostgresSpaPort) { $HadService = $true }
    if ($HadService) { Write-Host '-> dev environments down' }
    else { Write-Host '-> dev environments already down' }
}

function Start-BackgroundCommand(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$CommandText,
    [hashtable]$Environment,
    [string]$PidFile,
    [string]$LogFile
) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force | Out-Null
    Set-Content -LiteralPath $LogFile -Value '' -NoNewline
    $ScriptLines = @('$ErrorActionPreference = ''Stop''')
    foreach ($Entry in $Environment.GetEnumerator()) {
        $ScriptLines += "[Environment]::SetEnvironmentVariable($(ConvertTo-PowerShellLiteral $Entry.Key), $(ConvertTo-PowerShellLiteral ([string]$Entry.Value)), 'Process')"
    }
    $ScriptLines += "Set-Location -LiteralPath $(ConvertTo-PowerShellLiteral $WorkingDirectory)"
    $ScriptLines += '$ErrorActionPreference = ''Continue'''
    $ScriptLines += "$CommandText *>> $(ConvertTo-PowerShellLiteral $LogFile)"
    $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($ScriptLines -join "`r`n")))
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $PowerShellPath = Join-Path $PSHOME 'pwsh.exe'
    }
    else {
        $PowerShellPath = Join-Path $PSHOME 'powershell.exe'
    }
    $Process = Start-Process -FilePath $PowerShellPath `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $EncodedCommand) `
        -PassThru -WindowStyle Hidden
    $StartTicks = 0
    try { $StartTicks = $Process.StartTime.Ticks } catch { $StartTicks = 0 }
    Set-Content -LiteralPath $PidFile -Value "$($Process.Id) $StartTicks" -Encoding Ascii
    Write-Host "-> starting $Name (pid $($Process.Id))"
}

function Wait-ForService([string]$Name, [int]$Port, [string]$PidFile, [string]$LogFile, [int]$TimeoutSeconds) {
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Port $Port) {
            Write-Host "-> $Name up on http://localhost:$Port"
            return
        }
        if (-not (Test-ProcessIdFile $PidFile)) {
            Write-Host "ERROR: $Name exited during startup." -ForegroundColor Red
            Write-ErrorLog $LogFile
            throw "$Name failed to start."
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "ERROR: $Name did not start within ${TimeoutSeconds}s." -ForegroundColor Red
    Write-ErrorLog $LogFile
    throw "$Name startup timed out."
}

function Start-SqliteApi {
    if (Test-Port $ApiPort) { return }
    if (Test-ProcessIdFile $ApiPidFile) { return }
    Write-Host '-> starting SQLite API'
    $Environment = @{
        ASPNETCORE_URLS = "http://localhost:$ApiPort"
        MEDIAPAGER_Database__Provider = 'Sqlite'
        MEDIAPAGER_DB_PATH = $DbFile
        MEDIAPAGER_ConnectionStrings__AuthDatabase = "Data Source=$DbFile"
        MEDIAPAGER_Auth__SigningKeyPath = (Join-Path (Split-Path -Parent $DbFile) 'signing.key')
        MEDIAPAGER_Plugins__Directory = $PluginRoot
        ASPNETCORE_ENVIRONMENT = 'Development'
    }
    $Project = Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'
    $CommandText = "& dotnet run --no-launch-profile --project $(ConvertTo-PowerShellLiteral $Project)"
    Start-BackgroundCommand 'SQLite API' $RepoRoot $CommandText $Environment $ApiPidFile $ApiLog
}

function Start-Spa([int]$Port, [int]$TargetApiPort, [string]$Name, [string]$PidFile, [string]$LogFile) {
    if (Test-Port $Port) { return }
    if (Test-ProcessIdFile $PidFile) { return }
    Write-Host "-> starting $Name"
    $UiDirectory = Join-Path $RepoRoot 'MediaPager.App.Ui'
    $Environment = @{ VITE_API_BASE_URL = "http://localhost:$TargetApiPort" }
    $CommandText = "& npm.cmd run dev -- --host localhost --port $Port --strictPort"
    Start-BackgroundCommand $Name $UiDirectory $CommandText $Environment $PidFile $LogFile
}

function Start-PostgresApi {
    if (Test-Port $PostgresApiPort) { return }
    if (Test-ProcessIdFile $PostgresApiPidFile) { return }
    if ([string]::IsNullOrWhiteSpace($PostgresConnectionString)) {
        throw "MEDIAPAGER_ConnectionStrings__AuthDatabase is missing; configure it in the shell or $CredentialFile."
    }
    New-Item -ItemType Directory -Path $PostgresAppDir, (Join-Path $PostgresPluginDir 'community') -Force | Out-Null
    $PublishCommand = @(
        'publish', (Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'),
        '-c', 'Debug', '-o', $PostgresAppDir,
        "-p:MediaPagerOfficialPluginsDir=$(Join-Path $PostgresPluginDir 'official')",
        '--nologo', '-v:q'
    )
    Write-Host '-> building PostgreSQL API'
    $PublishExitCode = Invoke-NativeCommand 'dotnet' $PublishCommand $PostgresPublishLog
    if ($PublishExitCode -ne 0) {
        Write-Host 'ERROR: PostgreSQL API publish failed.' -ForegroundColor Red
        Write-ErrorLog $PostgresPublishLog
        throw 'PostgreSQL API publish failed.'
    }
    $Environment = @{
        ASPNETCORE_URLS = "http://localhost:$PostgresApiPort"
        MEDIAPAGER_Database__Provider = 'PostgreSQL'
        MEDIAPAGER_DB_PATH = ''
        MEDIAPAGER_Auth__SigningKeyPath = (Join-Path $RunDir 'postgres-signing.key')
        MEDIAPAGER_Plugins__Directory = $PostgresPluginDir
        ASPNETCORE_ENVIRONMENT = 'Development'
    }
    $CommandText = '& dotnet MediaPager.App.Api.dll'
    Write-Host '-> starting PostgreSQL API'
    Start-BackgroundCommand 'PostgreSQL API' $PostgresAppDir $CommandText $Environment $PostgresApiPidFile $PostgresApiLog
}

function Start-Environment {
    New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
    if ($UsingDefaultPostgresSettings) {
        Write-Host '-> using standard local PostGIS defaults (postgres/password, mediapager_dev)'
    }
    Ensure-Postgres
    Ensure-UiDependencies
    Warn-OptionalSetup
    if ((Test-Port $ApiPort) -and (Test-Port $SpaPort) -and (Test-Port $PostgresApiPort) -and (Test-Port $PostgresSpaPort)) {
        Write-Host '-> both dev environments already up'
        Write-DevelopmentNotice
        return
    }
    Start-PostgresApi
    Start-SqliteApi
    Start-Spa $PostgresSpaPort $PostgresApiPort 'PostgreSQL SPA' $PostgresSpaPidFile $PostgresSpaLog
    Start-Spa $SpaPort $ApiPort 'SQLite SPA' $SpaPidFile $SpaLog
    Wait-ForService 'SQLite API' $ApiPort $ApiPidFile $ApiLog 120
    Wait-ForService 'SQLite SPA' $SpaPort $SpaPidFile $SpaLog 60
    Wait-ForService 'PostgreSQL API' $PostgresApiPort $PostgresApiPidFile $PostgresApiLog 120
    Wait-ForService 'PostgreSQL SPA' $PostgresSpaPort $PostgresSpaPidFile $PostgresSpaLog 60
    Write-DevelopmentNotice
}

function Show-Environment {
    if ((Test-Port $ApiPort) -and (Test-Port $SpaPort) -and
        (Test-Port $PostgresApiPort) -and (Test-Port $PostgresSpaPort)) {
        Write-DevelopmentNotice
        return
    }
    Write-Host ''
    Write-Host 'MediaPager dev environment is not fully running' -ForegroundColor Cyan
    Write-Host "  SQLite API:     $(if (Test-Port $ApiPort) { 'up' } else { 'down' }) | http://localhost:$ApiPort"
    Write-Host "  SQLite SPA:     $(if (Test-Port $SpaPort) { 'up' } else { 'down' }) | http://localhost:$SpaPort"
    Write-Host "  PostgreSQL API: $(if (Test-Port $PostgresApiPort) { 'up' } else { 'down' }) | http://localhost:$PostgresApiPort"
    Write-Host "  PostgreSQL SPA: $(if (Test-Port $PostgresSpaPort) { 'up' } else { 'down' }) | http://localhost:$PostgresSpaPort"
    Write-Host ''
    Write-Host 'Start services: .\dev.ps1 up   (or .\dev.ps1 restart)'
    Write-Host 'Full reset:     .\dev.ps1 --refresh'
    Write-Host 'Note: --refresh deletes both dev databases and local plugin state; source/media files are untouched.' -ForegroundColor Yellow
}

function Stop-Environment {
    $Stopped = $false
    foreach ($Service in @(
        @{ Name = 'SQLite API'; PidFile = $ApiPidFile; Port = $ApiPort },
        @{ Name = 'SQLite SPA'; PidFile = $SpaPidFile; Port = $SpaPort },
        @{ Name = 'PostgreSQL API'; PidFile = $PostgresApiPidFile; Port = $PostgresApiPort },
        @{ Name = 'PostgreSQL SPA'; PidFile = $PostgresSpaPidFile; Port = $PostgresSpaPort }
    )) {
        if (Stop-ServicePair $Service.Name $Service.PidFile $Service.Port) { $Stopped = $true }
    }
    if ($Stopped) { Write-Host '-> dev environments down' }
    else { Write-Host '-> dev environments already down' }
}

function Reset-Environment {
    Stop-Environment
    if ([string]::IsNullOrWhiteSpace($PostgresConnectionString)) {
        throw 'MEDIAPAGER_ConnectionStrings__AuthDatabase is required to refresh both databases.'
    }
    $PreviousProvider = $env:MEDIAPAGER_Database__Provider
    $PreviousDbPath = $env:MEDIAPAGER_DB_PATH
    $PreviousConnectionString = $env:MEDIAPAGER_ConnectionStrings__AuthDatabase
    try {
        $env:MEDIAPAGER_Database__Provider = 'PostgreSQL'
        $env:MEDIAPAGER_DB_PATH = ''
        $env:MEDIAPAGER_ConnectionStrings__AuthDatabase = $PostgresConnectionString
        Write-Host '-> building API tooling for the PostgreSQL database drop'
        $BuildArguments = @('build', (Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'), '--nologo', '-v:q')
        $RefreshBuildExitCode = Invoke-NativeCommand 'dotnet' $BuildArguments $RefreshBuildLog
        if ($RefreshBuildExitCode -ne 0) {
            Write-Host 'ERROR: API build failed before PostgreSQL refresh.' -ForegroundColor Red
            Write-ErrorLog $RefreshBuildLog
            throw 'PostgreSQL refresh stopped before dropping either database.'
        }
        Write-Host '-> dropping configured PostgreSQL database through EF Core'
        $DropArguments = @(
            'ef', 'database', 'drop', '--force',
            '--project', (Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'),
            '--startup-project', (Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'),
            '--context', 'AuthDbContext', '--no-build'
        )
        $DropExitCode = Invoke-NativeCommand 'dotnet' $DropArguments $PostgresDropLog
        if ($DropExitCode -ne 0) {
            Write-Host 'ERROR: PostgreSQL database drop failed; SQLite data has not been deleted.' -ForegroundColor Red
            Write-ErrorLog $PostgresDropLog
            throw 'PostgreSQL database drop failed.'
        }
    }
    finally {
        $env:MEDIAPAGER_Database__Provider = $PreviousProvider
        $env:MEDIAPAGER_DB_PATH = $PreviousDbPath
        $env:MEDIAPAGER_ConnectionStrings__AuthDatabase = $PreviousConnectionString
    }
    $DbDirectory = Split-Path -Parent $DbFile
    Write-Host '-> deleting SQLite database files and signing key'
    foreach ($Path in @(
        $DbFile, "$DbFile-wal", "$DbFile-shm",
        (Join-Path $DbDirectory 'mediapager-auth.db'),
        (Join-Path $DbDirectory 'mediapager-auth.db-wal'),
        (Join-Path $DbDirectory 'mediapager-auth.db-shm'),
        (Join-Path $DbDirectory 'signing.key')
    )) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
    Write-Host '-> clearing local plugin/build state'
    $CleanArguments = @('clean', (Join-Path $RepoRoot 'MediaPager.App.Api\MediaPager.App.Api.csproj'), '--nologo', '-v:q')
    $CleanExitCode = Invoke-NativeCommand 'dotnet' $CleanArguments $RefreshBuildLog
    if ($CleanExitCode -ne 0) {
        Write-Host 'ERROR: dotnet clean failed during refresh.' -ForegroundColor Red
        Write-ErrorLog $RefreshBuildLog
        throw 'dotnet clean failed.'
    }
    if ([System.IO.Path]::IsPathRooted($PluginRoot) -and $PluginRoot -ne [System.IO.Path]::GetPathRoot($PluginRoot)) {
        Remove-Item -LiteralPath $PluginRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PostgresPluginDir, $PostgresAppDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '-> recreating databases, applying migrations, and seeding initial accounts'
    Start-Environment
}

switch ($Command.ToLowerInvariant()) {
    'help' { Write-Usage }
    '--help' { Write-Usage }
    '-h' { Write-Usage }
    'up' { Start-Environment }
    'down' { Stop-Environment }
    'restart' { Stop-Environment; Start-Environment }
    'show' { Show-Environment }
    'secrets' {
        $SigningState = if ($env:MEDIAPAGER_Auth__SigningKey) { 'set' } elseif ($env:MEDIAPAGER_EKEY) { 'legacy alias set' } else { 'not set' }
        $PostgresState = if ($PostgresConnectionString) { 'configured' } else { 'not configured' }
        Write-Host "Credentials file: $CredentialFile"
        Write-Host "TMDB key: $(if ($env:MEDIAPAGER_TMDB_API_KEY) { 'set' } else { 'not set' })"
        Write-Host "Signing key: $SigningState"
        Write-Host "Seed user: $(if ($env:MEDIAPAGER_SEED_USER) { 'set' } else { 'not set' })"
        Write-Host "Seed password: $(if ($env:MEDIAPAGER_SEED_PASS) { 'set' } else { 'not set' })"
        Write-Host "SQLite DB: $DbFile"
        Write-Host "PostgreSQL connection: $PostgresState"
    }
    '--refresh' { Reset-Environment }
    default { Write-Error "Unknown command '$Command'. Run .\dev.ps1 help."; exit 1 }
}
