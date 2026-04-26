#!/bin/bash
# ============================================================
#  ollamaui.sh — Launcher Ollama + Open WebUI (on-demand)
#  Version: 1.5.0
# ============================================================

VERSION="1.5.0"
REPO_URL="https://github.com/miradorventus/ollama-amd-plug-and-play"
RAW_URL="https://raw.githubusercontent.com/miradorventus/ollama-amd-plug-and-play/main"
LOCKFILE="/tmp/ollamaui.lock"
URL="http://127.0.0.1:3000"

# ─── Manual update via CLI ──────────────────────────────────
if [ "$1" = "--update" ]; then
  echo "🔄 Updating Ollama Plug & Play..."
  REPO_DIR="$HOME/ollama-amd-plug-and-play"
  if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR" && git pull && cp ollamaui.sh stopia.sh detect_browser.sh "$HOME/" 2>/dev/null
    chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"
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
    --filename=$HOME/ollamaui.log --width=700 --height=400 2>/dev/null
}

# ============================================================
# STEP 1 — ALREADY RUNNING ? (new tab if yes)
# ============================================================
if [ -f "$LOCKFILE" ]; then
  OLD_PID=$(cat "$LOCKFILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    # Real running instance — Firefox uses an isolated profile
    # so we can't open a new tab in it from outside
    zenity --info --title="OllamaUI — Already running" \
      --text="OllamaUI is already running.\n\nIt opened in an isolated Firefox profile.\nLook for the Firefox window with Open WebUI\nat 127.0.0.1:3000.\n\n💡 Tip: in that Firefox window, press Ctrl+T\nto open more tabs (e.g. parallel conversations).\n\nTo restart fresh: close that Firefox window first." \
      --width=450 --timeout=8 2>/dev/null
    exit 0
  else
    # Stale lockfile from a crashed run
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

# UFW: if active, must have rule for 11434
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
# STEP 3 — CHECK FOR UPDATES (silent if none)
# ============================================================
LATEST=$(curl -fsSL --max-time 3 "$RAW_URL/ollamaui.sh" 2>/dev/null | grep -oP '^VERSION="\K[^"]+' | head -1)

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
        cp ollamaui.sh stopia.sh detect_browser.sh "$HOME/" 2>/dev/null
        chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"
        echo "100"
      ) | zenity --progress --title="OllamaUI — Updating" \
          --text="Updating to $LATEST..." \
          --percentage=0 --auto-close --width=400 2>/dev/null
      
      zenity --info --title="✅ Updated" \
        --text="Updated to version $LATEST!\nRelaunching..." \
        --width=400 --timeout=2 2>/dev/null
      exec "$HOME/ollamaui.sh"
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
trap 'rm -f "$LOCKFILE"; "$HOME/stopia.sh" 2>/dev/null' EXIT

# ============================================================
# STEP 5 — START SERVICES (sudo via pkexec)
# ============================================================
echo "Requesting authentication..."
pkexec systemctl start ollama
START_STATUS=$?

if [ $START_STATUS -ne 0 ]; then
  # User cancelled or wrong password
  exit 0
fi

# ============================================================
# STEP 6 — LOADING WINDOW (Ollama + WebUI starting)
# ============================================================
(
  echo "# Checking Ollama connection..."
  for i in {1..15}; do
    curl -s http://127.0.0.1:11434 > /dev/null 2>&1 && break
    sleep 1
  done

  echo "# Starting Open WebUI..."
  docker stop open-webui >/dev/null 2>&1
  docker start open-webui > /dev/null 2>&1 || \
    docker run -d --name open-webui \
      -p 3000:8080 \
      --add-host=host.docker.internal:host-gateway \
      -v open-webui:/app/backend/data \
      ghcr.io/open-webui/open-webui:main > /dev/null 2>&1

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
# STEP 8 — OPEN BROWSER (unified, no "Click STOP" popup)
# ============================================================
BROWSER=$($HOME/detect_browser.sh | cut -d'|' -f1)

case "$BROWSER" in
  firefox)
    PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox/ollamaui-profile"
    [ ! -d "$HOME/snap/firefox" ] && PROFILE_DIR="$HOME/.mozilla/firefox/ollamaui-profile"
    mkdir -p "$PROFILE_DIR"
    # firefox blocks here until window closes — watchdog cleanup via trap
    firefox --no-remote --profile "$PROFILE_DIR" "$URL" 2>/dev/null
    ;;
  microsoft-edge|google-chrome|chromium-browser|chromium)
    "$BROWSER" --new-tab "$URL" 2>/dev/null &
    BROWSER_PID=$!
    wait $BROWSER_PID
    ;;
  *)
    # Fallback: xdg-open + poll for browser process closing
    xdg-open "$URL" 2>/dev/null
    sleep 3
    while pgrep -f "127.0.0.1:3000\|localhost:3000" > /dev/null 2>&1; do
      sleep 2
    done
    ;;
esac

# Trap EXIT does the cleanup (rm lockfile + stopia.sh)
