#!/bin/bash
# ============================================================
#  ollamaui.sh — Launcher Ollama + Open WebUI (on-demand)
# ============================================================

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


error_popup() {
  zenity --error --title="OllamaUI — Error" --text="$1" \
    --extra-button="View log" --width=400 2>/dev/null
  [ $? -eq 1 ] && zenity --text-info --title="Logs" \
    --filename=/home/ia/ollamaui.log --width=700 --height=400 2>/dev/null
}

# --- Start Ollama service (on-demand) ---
if ! systemctl is-active --quiet ollama; then
  echo "Starting Ollama service..."
  sudo systemctl start ollama 2>/dev/null
  sleep 3
fi

if ! curl -s http://localhost:11434 > /dev/null 2>&1; then
  error_popup "❌ Ollama is not responding.\nCheck: sudo systemctl status ollama"
  exit 1
fi

# --- Start Open WebUI (on-demand) ---
echo "Starting Open WebUI..."
docker start open-webui > /dev/null 2>&1 || \
  docker run -d --name open-webui \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    ghcr.io/open-webui/open-webui:main

for i in {1..30}; do curl -s http://localhost:3000 > /dev/null && break; sleep 1; done

if ! curl -s http://localhost:3000 > /dev/null 2>&1; then
  error_popup "❌ Open WebUI is not responding.\nCheck logs for details."
  exit 1
fi

# --- Open browser in a new tab (reuses existing window if possible) ---
BROWSER=$(/home/ia/detect_browser.sh | cut -d'|' -f1)
echo "Browser detected: $BROWSER"

case "$BROWSER" in
  firefox)
    # Use dedicated profile — waits for window close
    PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox/ollamaui-profile"
    mkdir -p "$PROFILE_DIR"
    firefox --no-remote --profile "$PROFILE_DIR" http://localhost:3000 2>/dev/null
    ;;
  microsoft-edge)
    # Open new tab in existing window, then wait
    MSG="✅ Open WebUI is ready in your browser!\n\nClick STOP below to close Ollama and free your GPU."
    zenity --info --title="OllamaUI" --text="$MSG" --ok-label="Stop" --width=400 2>/dev/null
    ;;
  google-chrome)
    MSG="✅ Open WebUI is ready in your browser!\n\nClick STOP below to close Ollama and free your GPU."
    zenity --info --title="OllamaUI" --text="$MSG" --ok-label="Stop" --width=400 2>/dev/null
    ;;
  *)
    xdg-open http://localhost:3000
    MSG="✅ Open WebUI is ready in your browser!\n\nClick STOP below to close Ollama and free your GPU."
    zenity --info --title="OllamaUI" --text="$MSG" --ok-label="Stop" --width=400 2>/dev/null
    ;;
esac

echo "Stopping services..."
/home/ia/stopia.sh
