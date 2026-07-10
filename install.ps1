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
# Instalar con todos los extras para soportar PostgreSQL, MySQL, SQL Server y Oracle
uv tool install --force --reinstall "$TargetDir[all]"
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

# --- 4b. Multitenant preflight (opcional) --------------------------------------
$MasterExample = Join-Path $TargetDir "master.example.toml"
if (Test-Path $MasterExample) {
    $BinDir = Join-Path $ConfigDir "bin"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

    $MasterToml = Join-Path $ConfigDir "master.toml"
    if (-not (Test-Path $MasterToml)) {
        Copy-Item $MasterExample $MasterToml
        Say "Master config copiado a $MasterToml (personalizalo)."
    } else {
        Say "Master config ya existe en $MasterToml (no se modifica)."
    }

    # Crear wrapper que use el Python del entorno de alux (con todos los drivers)
    $PreflightSrc = Join-Path $TargetDir "scripts\alux-preflight"
    $PreflightDst = Join-Path $BinDir "alux-preflight"
    $ToolPy = (Join-Path (uv tool dir) "alux\bin\python.exe")
    @"
@echo off
"$ToolPy" "$PreflightSrc" %*
"@ | Set-Content -Path $PreflightDst -Encoding UTF8
    Say "Preflight generator copiado a $PreflightDst (wrapper con entorno alux)."
}

# --- 4c. Verificar .env (necesario para interpolación de credenciales) ------
$EnvFile = Join-Path $ConfigDir ".env"
if (Test-Path $EnvFile) {
    try {
        $acl = Get-Acl $EnvFile
        $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $hasOthers = $false
        foreach ($rule in $acl.Access) {
            if ($rule.IdentityReference.Value -ne $owner -and $rule.FileSystemRights -ne "None") {
                $hasOthers = $true
                break
            }
        }
        if ($hasOthers) {
            Write-Host "[alux] WARNING: $EnvFile has permissive ACL — consider restricting access." -ForegroundColor Yellow
        }
    } catch {
        # Best-effort
    }
} else {
    if (Test-Path $MasterToml) {
        Say "No se encontro $EnvFile. Crealo con tus credenciales para que master.toml funcione:"
        Say "  Add-Content -Path $EnvFile -Value 'ALUX_DB_USER=tu_usuario'"
        Say "  Add-Content -Path $EnvFile -Value 'ALUX_DB_PASS=tu_password'"
    }
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
# Siempre intentar registrar si el directorio de config de OpenCode existe
# (OpenCode Desktop no siempre expone un comando "opencode" en PATH).
if (Test-Path $OpenCodeDir) {
    $OpenCodeConfig = Join-Path $OpenCodeDir "opencode.json"
    $OpenCodeConfigC = Join-Path $OpenCodeDir "opencode.jsonc"

    # Si existe .jsonc pero no .json, normalizar primero
    if ((Test-Path $OpenCodeConfigC) -and -not (Test-Path $OpenCodeConfig)) {
        $Content = Get-Content $OpenCodeConfigC -Raw
        # Strip single-line comments
        $Content = $Content -replace '//.*$', ''
        # Strip multi-line comments (simple, no nested)
        $Content = $Content -replace '/\*.*?\*/', ''
        # Remove trailing commas before } or ]
        $Content = $Content -replace ',(\s*[}\]])', '$1'
        $Content | Set-Content -Path $OpenCodeConfig -Encoding UTF8
    }

    # Buscar opencode.json o opencode.jsonc
    $OpenCodeConfig = Join-Path $OpenCodeDir "opencode.json"
    $OpenCodeConfigC = Join-Path $OpenCodeDir "opencode.jsonc"

    # Procesar ambos archivos si existen
    foreach ($CfgFile in @($OpenCodeConfig, $OpenCodeConfigC)) {
        if (-not (Test-Path $CfgFile)) { continue }

        $Content = Get-Content $CfgFile -Raw
        if ($Content -match '"alux"') {
            Say "OpenCode ($CfgFile): MCP 'alux' ya estaba registrado."
            continue
        }

        $Json = $Content | ConvertFrom-Json
        if (-not $Json.PSObject.Properties['mcp']) {
            $Json | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{})
        }
        if ($Json.mcp.PSObject.Properties['alux']) {
            Say "OpenCode ($CfgFile): MCP 'alux' ya estaba registrado."
        } else {
            $Json.mcp | Add-Member -NotePropertyName alux -NotePropertyValue ([pscustomobject]@{
                type    = "local"
                command = @($AluxBin)
                enabled = $true
            })
            New-Item -ItemType Directory -Force -Path $OpenCodeDir | Out-Null
            $Json | ConvertTo-Json -Depth 10 | Set-Content -Path $CfgFile -Encoding UTF8
            Say "OpenCode ($CfgFile): MCP 'alux' registrado."
        }
    }
} else {
    Say "OpenCode no detectado (directorio $OpenCodeDir no existe); se omite."
}

Say ""
Say "Listo. Edita $Config con tus conexiones y arranca claude/opencode."
Say "Para actualizar: cd $TargetDir; git pull; uv tool install --reinstall ."
