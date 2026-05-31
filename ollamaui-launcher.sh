#!/bin/bash
# ============================================================
#  ollamaui-launcher.sh — Launcher Ollama + Open WebUI (on-demand)
#  Version: 1.0.0
# ============================================================

VERSION="2.0.2"
REPO_URL="https://github.com/miradorventus/ollama-amd-plug-and-play"
RAW_URL="https://raw.githubusercontent.com/miradorventus/ollama-amd-plug-and-play/main"
LOCKFILE="/tmp/ollamaui.lock"
URL="http://127.0.0.1:3000"
# Self-detect: launcher uses its own folder (works for default ~/.ollamaui/ and custom locations)
OLLAMAUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure install dir exists
mkdir -p "$OLLAMAUI_DIR"

# Legacy migration: move old ollamaui.sh to ollamaui-launcher.sh
if [ -f "$OLLAMAUI_DIR/ollamaui.sh" ] && [ ! -f "$OLLAMAUI_DIR/ollamaui-launcher.sh" ]; then
  mv "$OLLAMAUI_DIR/ollamaui.sh" "$OLLAMAUI_DIR/ollamaui-launcher.sh" 2>/dev/null
fi

# Other legacy migrations (from v1.5.0)
for old_file in stopia.sh detect_browser.sh install_ollama.log ollamaui.log; do
  if [ -f "$HOME/$old_file" ] && [ ! -f "$OLLAMAUI_DIR/$old_file" ]; then
    mv "$HOME/$old_file" "$OLLAMAUI_DIR/$old_file" 2>/dev/null
  fi
done

# ─── Manual update via CLI ──────────────────────────────────
if [ "$1" = "--update" ]; then
  echo "🔄 Updating Ollama Plug & Play..."
  REPO_DIR="$HOME/ollama-amd-plug-and-play"
  if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR" && git pull && cp ollamaui-launcher.sh stopia.sh detect_browser.sh "$OLLAMAUI_DIR/" 2>/dev/null
    chmod +x "$OLLAMAUI_DIR/ollamaui-launcher.sh" "$OLLAMAUI_DIR/stopia.sh" "$OLLAMAUI_DIR/detect_browser.sh"
    echo "✅ Updated"
  else
    echo "⚠️ Repo not found at $REPO_DIR"
  fi
  exit 0
fi

error_popup() {
  zenity --error --title="OllamaUI — Error" --text="$1" \
    --extra-button="View log" --width=400 2>/dev/null
  [ $? -eq 1 ] && zenity --text-info --title="Logs" \
    --filename="$OLLAMAUI_DIR/ollamaui.log" --width=700 --height=400 2>/dev/null
}

# ============================================================
# AUTO GPU CONFIG — ensures HIP_VISIBLE_DEVICES is set on multi-GPU AMD setups
# Runs silently, only acts if needed
# ============================================================
auto_configure_gpu() {
  local OVERRIDE_FILE="/etc/systemd/system/ollama.service.d/override.conf"
  
  # Skip if no override file (Ollama not installed yet)
  [ ! -f "$OVERRIDE_FILE" ] && return 0
  
  # Skip if HIP_VISIBLE_DEVICES already set (respect user customization)
  if grep -q "HIP_VISIBLE_DEVICES" "$OVERRIDE_FILE" 2>/dev/null; then
    return 0
  fi
  
  # Detect AMD dGPU index (only relevant if 2+ AMD GPUs)
  local AMD_GPU_COUNT=0
  local DGPU_INDEX=-1
  local INDEX=0
  
  while IFS= read -r line; do
    if echo "$line" | grep -qiE "Navi|RX [0-9]"; then
      [ "$DGPU_INDEX" -eq -1 ] && DGPU_INDEX=$INDEX
      AMD_GPU_COUNT=$((AMD_GPU_COUNT+1))
      INDEX=$((INDEX+1))
    elif echo "$line" | grep -qiE "AMD|ATI"; then
      AMD_GPU_COUNT=$((AMD_GPU_COUNT+1))
      INDEX=$((INDEX+1))
    fi
  done < <(lspci | grep -E "VGA|3D")
  
  # Only configure if 2+ AMD GPUs (split iGPU+dGPU setup)
  [ "$AMD_GPU_COUNT" -lt 2 ] && return 0
  [ "$DGPU_INDEX" -lt 0 ] && return 0
  
  # Add HIP_VISIBLE_DEVICES via pkexec (silent, no popup)
  local TMP=$(mktemp)
  cat "$OVERRIDE_FILE" > "$TMP"
  echo "Environment=\"HIP_VISIBLE_DEVICES=$DGPU_INDEX\"" >> "$TMP"
  
  pkexec sh -c "cat '$TMP' > '$OVERRIDE_FILE' && systemctl daemon-reload" 2>/dev/null
  rm -f "$TMP"
}

# ============================================================
# STEP 1 — ALREADY RUNNING ? (info popup if yes)
# ============================================================
if [ -f "$LOCKFILE" ]; then
  OLD_PID=$(cat "$LOCKFILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    zenity --info --title="OllamaUI — Already running" \
      --text="OllamaUI is already running.\n\nIt opened in an isolated Firefox profile.\nLook for the Firefox window with Open WebUI\nat 127.0.0.1:3000.\n\n💡 Tip: in that Firefox window, press Ctrl+T\nto open more tabs (e.g. parallel conversations).\n\nTo restart fresh: close that Firefox window first." \
      --width=450 --timeout=8 2>/dev/null
    exit 0
  else
    rm -f "$LOCKFILE"
  fi
fi

# ============================================================
# STEP 2 — INTEGRITY CHECK (silent if all OK)
# ============================================================
INT_MISSING=""
command -v ollama &>/dev/null || INT_MISSING+="\n  • Ollama binary"

if ! docker ps -a --filter name=open-webui --format "{{.Names}}" 2>/dev/null | grep -q open-webui; then
  INT_MISSING+="\n  • Open WebUI container"
fi

[ -f /etc/sudoers.d/ollama-nopasswd-stop ] || INT_MISSING+="\n  • Sudoers config (NOPASSWD stop)"

if command -v ufw &>/dev/null && \
   sudo -n ufw status 2>/dev/null | head -1 | grep -qiE "active|actif"; then
  if ! sudo -n ufw status 2>/dev/null | grep -q "11434"; then
    INT_MISSING+="\n  • UFW rule for Docker → port 11434"
  fi
fi

if [ -n "$INT_MISSING" ]; then
  zenity --question --title="OllamaUI — Repair needed" \
    --text="Some components are missing or broken:$INT_MISSING\n\nRun the installer to fix only what's missing." \
    --ok-label="✅ Repair now" --cancel-label="❌ Cancel" --width=500 2>/dev/null
  if [ $? -eq 0 ]; then
    if [ -x "$HOME/ollama-amd-plug-and-play/install_ollama.sh" ]; then
      exec "$HOME/ollama-amd-plug-and-play/install_ollama.sh"
    else
      error_popup "Installer not found at\n$HOME/ollama-amd-plug-and-play/install_ollama.sh\n\nClone the repo first:\ngit clone $REPO_URL"
    fi
  fi
  exit 0
fi

# ============================================================
# STEP 2.5 — AUTO GPU CONFIG (silent, only if needed)
# ============================================================
auto_configure_gpu

# ============================================================
# STEP 3 — CHECK FOR UPDATES (silent if none)
# ============================================================
LATEST=$(curl -fsSL --max-time 3 "$RAW_URL/ollamaui-launcher.sh" 2>/dev/null | grep -oP '^VERSION="\K[^"]+' | head -1)

if [ -n "$LATEST" ] && [ "$LATEST" != "$VERSION" ]; then
  zenity --question \
    --title="OllamaUI — Update available 🎉" \
    --text="A new version is available!\n\nCurrent: $VERSION\nLatest:  $LATEST\n\nUpdate now?" \
    --width=400 2>/dev/null
  if [ $? -eq 0 ]; then
    REPO_DIR="$HOME/ollama-amd-plug-and-play"
    if [ -d "$REPO_DIR/.git" ]; then
      (
        echo "20"; echo "# Pulling updates..."
        cd "$REPO_DIR" && git pull > /dev/null 2>&1
        echo "60"; echo "# Copying scripts..."
        cp ollamaui-launcher.sh stopia.sh detect_browser.sh "$OLLAMAUI_DIR/" 2>/dev/null
        chmod +x "$OLLAMAUI_DIR/ollamaui-launcher.sh" "$OLLAMAUI_DIR/stopia.sh" "$OLLAMAUI_DIR/detect_browser.sh"
        echo "100"
      ) | zenity --progress --title="OllamaUI — Updating" \
          --text="Updating to $LATEST..." \
          --percentage=0 --auto-close --width=400 2>/dev/null
      
      zenity --info --title="✅ Updated" \
        --text="Updated to version $LATEST!\nRelaunching..." \
        --width=400 --timeout=2 2>/dev/null
      exec "$OLLAMAUI_DIR/ollamaui-launcher.sh"
    else
      zenity --warning --title="Manual update needed" \
        --text="Please update manually:\ncd ~/ollama-amd-plug-and-play && git pull" \
        --width=400 2>/dev/null
    fi
  fi
fi

# ============================================================
# STEP 4 — CREATE LOCKFILE + CLEANUP TRAP
# ============================================================
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; "$OLLAMAUI_DIR/stopia.sh" 2>/dev/null' EXIT

# ============================================================
# STEP 5 — START SERVICES (sudo via pkexec)
# ============================================================
echo "Requesting authentication..."
pkexec systemctl start ollama
START_STATUS=$?

if [ $START_STATUS -ne 0 ]; then
  exit 0
fi

# Start Open WebUI container (idempotent: safe if already running)
docker start open-webui > /dev/null 2>&1

# ============================================================
# STEP 6 — LOADING WINDOW (Ollama + WebUI starting)
# ============================================================
(
  echo "# Checking Ollama connection..."
  for i in {1..15}; do
    curl -s http://127.0.0.1:11434 > /dev/null 2>&1 && break
    sleep 1
  done

  echo "# Waiting for Open WebUI container to be ready..."

  echo "# Waiting for Open WebUI to be ready..."
  for i in {1..30}; do
    curl -s http://127.0.0.1:3000 > /dev/null 2>&1 && break
    sleep 1
  done

  echo "# Almost ready..."
  sleep 1
) | zenity --progress \
    --title="OllamaUI — Starting" \
    --text="Initializing..." \
    --pulsate --auto-close --no-cancel --width=450 2>/dev/null

# ============================================================
# STEP 7 — VERIFY ALL SERVICES UP
# ============================================================
if ! curl -s http://127.0.0.1:11434 > /dev/null 2>&1; then
  error_popup "❌ Ollama is not responding.\nCheck: sudo systemctl status ollama"
  exit 1
fi

if ! curl -s http://127.0.0.1:3000 > /dev/null 2>&1; then
  error_popup "❌ Open WebUI is not responding.\nCheck logs for details."
  exit 1
fi

# ============================================================
# STEP 8 — OPEN BROWSER
# ============================================================
BROWSER=$("$OLLAMAUI_DIR/detect_browser.sh" | cut -d'|' -f1)

case "$BROWSER" in
  firefox)
    # WebApp Manager pattern: isolated profile in standard location
    PROFILE_DIR="$HOME/.local/share/ice/firefox/OllamaUI"
    mkdir -p "$PROFILE_DIR"
    ICON_PATH="$HOME/ollama-amd-plug-and-play/icon.png"
    [ ! -f "$ICON_PATH" ] && ICON_PATH=""
    XAPP_FORCE_GTKWINDOW_ICON="$ICON_PATH" firefox \
      --class WebApp-OllamaUI \
      --name WebApp-OllamaUI \
      --profile "$PROFILE_DIR" \
      --no-remote \
      "$URL" 2>/dev/null
    ;;
  microsoft-edge|google-chrome|chromium-browser|chromium)
    "$BROWSER" --new-tab "$URL" 2>/dev/null &
    BROWSER_PID=$!
    wait $BROWSER_PID
    ;;
  *)
    xdg-open "$URL" 2>/dev/null
    sleep 3
    while pgrep -f "127.0.0.1:3000\|localhost:3000" > /dev/null 2>&1; do
      sleep 2
    done
    ;;
esac

# Trap EXIT does the cleanup (rm lockfile + stopia.sh)
