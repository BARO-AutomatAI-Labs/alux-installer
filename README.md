# Alux Installer

Instalador público para el servidor MCP de bases de datos **alux**.

## ¿Qué hace?

Este repositorio contiene los scripts de instalación para cualquier plataforma. Cuando lo ejecutas:

1. **Clona** el repositorio privado [`BARO-AutomatAI-Labs/alux`](https://github.com/BARO-AutomatAI-Labs/alux) en tu máquina local (`~/.alux` en Unix, `%USERPROFILE%\.alux` en Windows).
2. **Instala** el paquete Python `alux` como herramienta global usando [uv](https://docs.astral.sh/uv/).
3. **Crea** la configuración por defecto en `~/.config/alux/config.toml` (Unix) o `%APPDATA%\alux\config.toml` (Windows).
4. **Registra** automáticamente el MCP en **Claude Code** (scope `user`) y en **OpenCode** si están instalados.

## Requisitos

- [GitHub CLI (`gh`)](https://cli.github.com/) instalado y autenticado (`gh auth login`).
- Acceso al repositorio privado `BARO-AutomatAI-Labs/alux`.
- No necesitas tener Python instalado: `uv` se instala automáticamente si no lo tienes.

## Instalación

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/BARO-AutomatAI-Labs/alux-installer/main/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/BARO-AutomatAI-Labs/alux-installer/main/install.ps1 | iex
```

## Variables de entorno

Ambos scripts respetan estas variables para personalizar el comportamiento:

| Variable | Descripción | Default |
|---|---|---|
| `ALUX_REPO` | Repo privado a clonar (`owner/repo`) | `BARO-AutomatAI-Labs/alux` |
| `ALUX_DIR` | Directorio donde clonar el repo | `~/.alux` / `%USERPROFILE%\.alux` |

Ejemplo:

```bash
ALUX_REPO=mi-org/alux-fork ALUX_DIR=/opt/alux sh install.sh
```

## ¿Qué ocurre tras ejecutar?

- El comando `alux` quedará disponible globalmente.
- Se crea el archivo de configuración con una base de datos SQLite de demostración.
- El servidor MCP se registra en Claude Code y OpenCode, estando listo para usarse en cualquier proyecto.

## Actualización

Para actualizar `alux` cuando haya cambios en el repo privado:

### Linux / macOS

```bash
cd ~/.alux && git pull && uv tool install --reinstall .
```

### Windows

```powershell
cd ~/.alux; git pull; uv tool install --reinstall .
```

O simplemente vuelve a ejecutar el instalador original.

## Licencia

MIT — ver el repositorio principal de alux.
