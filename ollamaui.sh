#!/bin/bash
# ============================================================
#  ollamaui.sh — Launcher Ollama + Open WebUI (on-demand)
#  Version: 1.1.0
# ============================================================

VERSION="1.1.0"
REPO_URL="https://github.com/miradorventus/ollama-amd-plug-and-play"
RAW_URL="https://raw.githubusercontent.com/miradorventus/ollama-amd-plug-and-play/main"

# --- Manual update via CLI ---
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
    --filename=/home/ia/ollamaui.log --width=700 --height=400 2>/dev/null
}


# --- Sudo auth first ---
if ! sudo -n true 2>/dev/null; then
  PASSWORD=$(zenity --password --title="OllamaUI" \
    --text="Enter your password to start Ollama:" --width=400 2>/dev/null)
  [ $? -ne 0 ] && exit 0
  echo "$PASSWORD" | sudo -S -v 2>/dev/null || {
    zenity --error --title="Error" --text="Wrong password." --width=300 2>/dev/null
    exit 1
  }
fi


# --- Clean any previous session ---
docker stop open-webui >/dev/null 2>&1
sudo systemctl stop ollama >/dev/null 2>&1
sleep 1

# --- Check for updates in background (silent) ---
UPDATE_INFO_FILE=$(mktemp)
(
  LATEST=$(curl -fsSL --max-time 3 "$RAW_URL/ollamaui.sh" 2>/dev/null | grep -oP '^VERSION="\K[^"]+' | head -1)
  if [ -n "$LATEST" ] && [ "$LATEST" != "$VERSION" ]; then
    echo "$LATEST" > "$UPDATE_INFO_FILE"
  fi
) &
UPDATE_PID=$!

  sudo -v 2>/dev/null
# --- LOADING WINDOW — shows progress while everything starts ---
(
  echo "# Starting Ollama service..."
  sudo systemctl start ollama 2>/dev/null
  sleep 2

  echo "# Checking Ollama connection..."
  for i in {1..15}; do
    curl -s http://127.0.0.1:11434 > /dev/null 2>&1 && break
    sleep 1
  done

  echo "# Starting Open WebUI..."
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
    --pulsate --auto-close \
    --no-cancel --width=450 2>/dev/null

# --- Verify everything is up ---
if ! curl -s http://127.0.0.1:11434 > /dev/null 2>&1; then
  error_popup "❌ Ollama is not responding.\nCheck: sudo systemctl status ollama"
  exit 1
fi

if ! curl -s http://127.0.0.1:3000 > /dev/null 2>&1; then
  error_popup "❌ Open WebUI is not responding.\nCheck logs for details."
  exit 1
fi

# --- Show update popup if available ---
wait $UPDATE_PID 2>/dev/null
if [ -s "$UPDATE_INFO_FILE" ]; then
  LATEST=$(cat "$UPDATE_INFO_FILE")
  rm -f "$UPDATE_INFO_FILE"
  (
    zenity --question \
      --title="OllamaUI — Update available 🎉" \
      --text="A new version is available!\n\nCurrent: $VERSION\nLatest:  $LATEST\n\nUpdate now? (will apply on next launch)" \
      --width=400 2>/dev/null
    if [ $? -eq 0 ]; then
      REPO_DIR="$HOME/ollama-amd-plug-and-play"
      if [ -d "$REPO_DIR/.git" ]; then
        cd "$REPO_DIR" && git pull > /dev/null 2>&1
        cp ollamaui.sh stopia.sh detect_browser.sh "$HOME/" 2>/dev/null
        chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"
        zenity --info --title="Updated" \
          --text="✅ Updated to $LATEST!\nRestart OllamaUI to apply." \
          --width=400 2>/dev/null
      else
        zenity --warning --title="Manual update needed" \
          --text="Please update manually:\ncd ~/ollama-amd-plug-and-play && git pull" \
          --width=400 2>/dev/null
      fi
    fi
  ) &
fi
rm -f "$UPDATE_INFO_FILE"

# --- Open browser ---
BROWSER=$(/home/ia/detect_browser.sh | cut -d'|' -f1)

case "$BROWSER" in
  firefox)
    PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox/ollamaui-profile"
    mkdir -p "$PROFILE_DIR"
    firefox --no-remote --profile "$PROFILE_DIR" http://127.0.0.1:3000 2>/dev/null
    ;;
  microsoft-edge)
    microsoft-edge --new-tab http://127.0.0.1:3000 2>/dev/null &
    zenity --info --title="OllamaUI" \
      --text="✅ Open WebUI is ready!\n\nClick STOP to close Ollama and free your GPU." \
      --ok-label="Stop" --width=400 2>/dev/null
    ;;
  google-chrome)
    google-chrome --new-tab http://127.0.0.1:3000 2>/dev/null &
    zenity --info --title="OllamaUI" \
      --text="✅ Open WebUI is ready!\n\nClick STOP to close Ollama and free your GPU." \
      --ok-label="Stop" --width=400 2>/dev/null
    ;;
  *)
    xdg-open http://127.0.0.1:3000
    zenity --info --title="OllamaUI" \
      --text="✅ Open WebUI is ready!\n\nClick STOP to close Ollama and free your GPU." \
      --ok-label="Stop" --width=400 2>/dev/null
    ;;
esac

# --- Cleanup on exit ---
/home/ia/stopia.sh
