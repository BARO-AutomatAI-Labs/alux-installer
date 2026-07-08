#!/bin/sh
# Instalador público de alux — clona repo privado e instala.
#
#   curl -fsSL https://raw.githubusercontent.com/BARO-AutomatAI-Labs/alux-installer/main/install.sh | sh
#
# Requiere: gh (GitHub CLI) autenticado con acceso al repo privado.

set -eu

REPO="${ALUX_REPO:-BARO-AutomatAI-Labs/alux}"
TARGET_DIR="${ALUX_DIR:-$HOME/.alux}"
REPO_URL="https://github.com/${REPO}"

# Validación de seguridad: nunca operar sobre directorio vacío
if [ -z "$TARGET_DIR" ] || [ "$TARGET_DIR" = "/" ]; then
  say "ERROR: TARGET_DIR no puede ser raíz o vacío."
  exit 1
fi

say() { printf '\033[1;36m[alux]\033[0m %s\n' "$*"; }

# --- 0. GitHub CLI ---------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  say "ERROR: necesitas GitHub CLI (gh)."
  say "  macOS: brew install gh"
  say "  Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  say "ERROR: no has iniciado sesión en GitHub."
  say "  Ejecuta: gh auth login"
  exit 1
fi

say "Validando acceso al repo privado..."
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  say "ERROR: no tienes acceso a $REPO"
  exit 1
fi

# --- 1. Clonar repo privado -------------------------------------------------
if [ -d "$TARGET_DIR/.git" ]; then
  say "Actualizando repo en $TARGET_DIR..."
  cd "$TARGET_DIR"
  git pull
else
  say "Clonando repo privado..."
  rm -rf "$TARGET_DIR"
  gh repo clone "$REPO" "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

# --- 2. uv ------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  say "Instalando uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || {
    say "ERROR: uv no quedó en PATH. Abre una terminal nueva y reintenta."
    exit 1
  }
fi

# --- 3. Instalar alux desde el directorio clonado ---------------------------
say "Instalando alux desde $TARGET_DIR..."
uv tool install --force --reinstall "$TARGET_DIR"

BIN_DIR="$(uv tool dir --bin)"
ALUX_BIN="$BIN_DIR/alux"
TOOL_PY="$(uv tool dir)/alux/bin/python"

# --- 4. Config por defecto ---------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/alux"
CONFIG="$CONFIG_DIR/config.toml"
if [ -f "$CONFIG" ]; then
  say "Config existente en $CONFIG (no se modifica)."
else
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG" <<EOF
# Configuración de alux. Agrega aquí tus conexiones; ver ejemplos en
# ${REPO_URL}/blob/main/config.example.toml

# Demo local para verificar que el servidor funciona.
[datasources.demo]
url = "sqlite:///$CONFIG_DIR/demo.db"
readonly = false
description = "SQLite de demostración"
EOF
  say "Config creada en $CONFIG — edítala para agregar tus bases de datos."
fi

# --- 5. Claude Code -----------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  if claude mcp get alux >/dev/null 2>&1; then
    say "Claude Code: MCP 'alux' ya estaba registrado."
  else
    claude mcp add --scope user alux -- "$ALUX_BIN"
    say "Claude Code: MCP 'alux' registrado."
  fi
else
  say "Claude Code no detectado. Para registrarlo después:"
  say "  claude mcp add --scope user alux -- $ALUX_BIN"
fi

# --- 6. OpenCode --------------------------------------------------------------
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
if command -v opencode >/dev/null 2>&1 || [ -d "$OPENCODE_DIR" ]; then
  RESULT="$("$TOOL_PY" - "$OPENCODE_DIR/opencode.json" "$ALUX_BIN" <<'PYEOF'
import json, sys
from pathlib import Path

path, alux_bin = Path(sys.argv[1]), sys.argv[2]
config = json.loads(path.read_text()) if path.is_file() else {
    "$schema": "https://opencode.ai/config.json"
}
mcp = config.setdefault("mcp", {})
if "alux" in mcp:
    print("ya")
else:
    mcp["alux"] = {"type": "local", "command": [alux_bin], "enabled": True}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    print("ok")
PYEOF
)"
  if [ "$RESULT" = "ya" ]; then
    say "OpenCode: MCP 'alux' ya estaba registrado."
  else
    say "OpenCode: MCP 'alux' registrado."
  fi
else
  say "OpenCode no detectado; se omite."
fi

say ""
say "Listo. Edita $CONFIG con tus conexiones y arranca claude/opencode."
say "Para actualizar: cd $TARGET_DIR && git pull && uv tool install --reinstall ."
