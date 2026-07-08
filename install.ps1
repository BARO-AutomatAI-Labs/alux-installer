# Instalador público de alux para Windows (PowerShell 5.1+).
#
#   irm https://raw.githubusercontent.com/BARO-AutomatAI-Labs/alux-installer/main/install.ps1 | iex
#
# Requiere: gh (GitHub CLI) autenticado con acceso al repo privado.

$ErrorActionPreference = "Stop"

$Repo = if ($env:ALUX_REPO) { $env:ALUX_REPO } else { "BARO-AutomatAI-Labs/alux" }
$TargetDir = if ($env:ALUX_DIR) { $env:ALUX_DIR } else { Join-Path $env:USERPROFILE ".alux" }
$RepoUrl = "https://github.com/$Repo"

function Say($Message) { Write-Host "[alux] $Message" -ForegroundColor Cyan }

# --- 0. GitHub CLI ------------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Say "ERROR: necesitas GitHub CLI (gh)."
    Say "  Windows: winget install --id GitHub.cli"
    Say "  O descargalo desde: https://cli.github.com/"
    throw "gh no encontrado."
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Say "ERROR: no has iniciado sesion en GitHub."
    Say "  Ejecuta: gh auth login"
    throw "gh no autenticado."
}

Say "Validando acceso al repo privado..."
gh repo view $Repo *> $null
if ($LASTEXITCODE -ne 0) {
    Say "ERROR: no tienes acceso a $Repo"
    throw "Acceso denegado al repo privado."
}

# --- 1. Clonar repo privado ----------------------------------------------------
if (Test-Path (Join-Path $TargetDir ".git")) {
    Say "Actualizando repo en $TargetDir..."
    $OriginalLocation = Get-Location
    try {
        Set-Location $TargetDir
        git pull
        if ($LASTEXITCODE -ne 0) { throw "git pull fallo." }
    } finally {
        Set-Location $OriginalLocation
    }
} else {
    Say "Clonando repo privado..."
    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
    gh repo clone $Repo $TargetDir
    if ($LASTEXITCODE -ne 0) { throw "gh repo clone fallo." }
}

# --- 2. uv ---------------------------------------------------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Say "Instalando uv..."
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw "uv no quedo en PATH. Abre una terminal nueva y reintenta."
    }
}

# --- 3. Instalar alux desde el directorio clonado -----------------------------
Say "Instalando alux desde $TargetDir..."
uv tool install --force --reinstall $TargetDir
if ($LASTEXITCODE -ne 0) { throw "uv tool install fallo." }

$BinDir = (uv tool dir --bin).Trim()
$AluxBin = Join-Path $BinDir "alux.exe"

# --- 4. Config por defecto -----------------------------------------------------
$ConfigDir = Join-Path $env:APPDATA "alux"
$Config = Join-Path $ConfigDir "config.toml"
if (Test-Path $Config) {
    Say "Config existente en $Config (no se modifica)."
} else {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $DemoDb = ($ConfigDir -replace '\\', '/') + "/demo.db"
    @"
# Configuracion de alux. Agrega aqui tus conexiones; ver ejemplos en
# $RepoUrl/blob/main/config.example.toml

# Demo local para verificar que el servidor funciona.
[datasources.demo]
url = "sqlite:///$DemoDb"
readonly = false
description = "SQLite de demostracion"
"@ | Set-Content -Path $Config -Encoding UTF8
    Say "Config creada en $Config — editala para agregar tus bases de datos."
}

# --- 5. Claude Code -----------------------------------------------------------
if (Get-Command claude -ErrorAction SilentlyContinue) {
    claude mcp get alux *> $null
    if ($LASTEXITCODE -eq 0) {
        Say "Claude Code: el MCP 'alux' ya estaba registrado."
    } else {
        claude mcp add --scope user alux -- $AluxBin
        if ($LASTEXITCODE -ne 0) { throw "claude mcp add fallo." }
        Say "Claude Code: MCP 'alux' registrado."
    }
} else {
    Say "Claude Code no detectado. Para registrarlo despues:"
    Say "  claude mcp add --scope user alux -- $AluxBin"
}

# --- 6. OpenCode ---------------------------------------------------------------
$OpenCodeDir = Join-Path $env:USERPROFILE ".config\opencode"
if ((Get-Command opencode -ErrorAction SilentlyContinue) -or (Test-Path $OpenCodeDir)) {
    $OpenCodeConfig = Join-Path $OpenCodeDir "opencode.json"
    $Json = if (Test-Path $OpenCodeConfig) {
        Get-Content $OpenCodeConfig -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{ '$schema' = "https://opencode.ai/config.json" }
    }
    if (-not $Json.PSObject.Properties['mcp']) {
        $Json | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{})
    }
    if ($Json.mcp.PSObject.Properties['alux']) {
        Say "OpenCode: el MCP 'alux' ya estaba registrado."
    } else {
        $Json.mcp | Add-Member -NotePropertyName alux -NotePropertyValue ([pscustomobject]@{
            type    = "local"
            command = @($AluxBin)
            enabled = $true
        })
        New-Item -ItemType Directory -Force -Path $OpenCodeDir | Out-Null
        $Json | ConvertTo-Json -Depth 10 | Set-Content -Path $OpenCodeConfig -Encoding UTF8
        Say "OpenCode: MCP 'alux' registrado."
    }
} else {
    Say "OpenCode no detectado; se omite."
}

Say ""
Say "Listo. Edita $Config con tus conexiones y arranca claude/opencode."
Say "Para actualizar: cd $TargetDir; git pull; uv tool install --reinstall ."
