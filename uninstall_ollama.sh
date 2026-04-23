#!/bin/bash
# ============================================================
#  uninstall_ollama.sh
# ============================================================

LOG_FILE="$HOME/uninstall_ollama.log"
STATUS_FILE=$(mktemp)

if ! command -v zenity &>/dev/null; then
  sudo apt install zenity -y
fi

if ! sudo -n true 2>/dev/null; then
  PASSWORD=$(zenity --password \
    --title="Authentication required" \
    --text="Enter your password to uninstall:" \
    --width=400 2>/dev/null)
  [ $? -ne 0 ] && exit 0
  echo "$PASSWORD" | sudo -S -v 2>/dev/null || {
    zenity --error --title="Error" --text="❌ Wrong password." --width=300 2>/dev/null
    exit 1
  }
fi

MSG="⚠️ Uninstall Ollama + Open WebUI?\n\nThis will remove:\n• Ollama service and binaries\n• Open WebUI Docker container and image\n• Desktop shortcut and scripts\n\nYour downloaded models in ~/.ollama will be KEPT."

zenity --question --title="Uninstall Ollama" --text="$MSG" --width=450 2>/dev/null
[ $? -ne 0 ] && exit 0

echo "=== Uninstall log — $(date) ===" > "$LOG_FILE"
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }

uninstall() {
  log "=== Uninstalling Open WebUI (Docker) ==="
  docker stop open-webui 2>/dev/null
  docker rm open-webui 2>/dev/null
  docker rmi -f ghcr.io/open-webui/open-webui:main 2>/dev/null
  log "Open WebUI removed"

  log "=== Uninstalling Ollama (native) ==="
  sudo systemctl stop ollama 2>/dev/null
  sudo systemctl disable ollama 2>/dev/null
  sudo rm -f /etc/systemd/system/ollama.service
  sudo rm -rf /etc/systemd/system/ollama.service.d
  sudo rm -f /usr/local/bin/ollama
  sudo rm -rf /usr/local/lib/ollama
  sudo userdel ollama 2>/dev/null
  sudo groupdel ollama 2>/dev/null
  sudo systemctl daemon-reload
  log "Ollama removed"

  log "=== Removing scripts and shortcuts ==="
  rm -f ~/ollamaui.sh ~/stopia.sh ~/detect_browser.sh
  rm -f ~/Bureau/OllamaUI.desktop ~/Desktop/OllamaUI.desktop

  log "✅ Uninstall complete!"
  log "Your models are preserved in ~/.ollama"
  echo "SUCCESS" > "$STATUS_FILE"
}

uninstall &
PID=$!

tail -n 15 -f "$LOG_FILE" 2>/dev/null | zenity --text-info \
  --title="Ollama — Uninstalling..." \
  --width=600 --height=300 --no-wrap --ok-label="Close" 2>/dev/null &
ZENITY_PID=$!

while kill -0 $PID 2>/dev/null; do sleep 1; done
kill $ZENITY_PID 2>/dev/null

STATUS=$(cat "$STATUS_FILE" 2>/dev/null)
rm -f "$STATUS_FILE"

if [ "$STATUS" = "SUCCESS" ]; then
  zenity --info --title="Uninstall complete" \
    --text="✅ Ollama + Open WebUI uninstalled.\n\nYour models are still in ~/.ollama\n(delete manually to free space)" \
    --width=400 2>/dev/null
else
  zenity --warning --title="Uninstall" --text="⚠️ Uninstall interrupted." --width=350 2>/dev/null
fi

exit 0
