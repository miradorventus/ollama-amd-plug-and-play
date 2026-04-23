#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Ollama (native, on-demand) + Open WebUI (Docker, on-demand)
#  AMD ROCm — Ubuntu 24.04
#  POLICY: Services start ONLY when OllamaUI is launched
# ============================================================

LOG_FILE="$HOME/install_ollama.log"
STATUS_FILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v zenity &>/dev/null; then
  sudo apt install zenity -y
fi

if ! sudo -n true 2>/dev/null; then
  PASSWORD=$(zenity --password \
    --title="Authentication required" \
    --text="Enter your password to install Ollama + Open WebUI:" \
    --width=400 2>/dev/null)
  [ $? -ne 0 ] && exit 0
  echo "$PASSWORD" | sudo -S -v 2>/dev/null || {
    zenity --error --title="Error" --text="❌ Wrong password." --width=300 2>/dev/null
    exit 1
  }
fi

MSG_WELCOME="Welcome to the Ollama + Open WebUI installer\n\nThis will install:\n• Ollama (native, via official script)\n• Open WebUI (Docker container)\n\nPOLICY: On-demand only\n• Services start when you launch OllamaUI\n• Services stop when you close the browser\n• Nothing runs at boot — saves power!\n\nRequirements:\n• Ubuntu 24.04\n• AMD GPU with ROCm support\n• Docker (will be installed if missing)\n• ~20 GB free disk space\n\nLog: $LOG_FILE"
MSG_SUCCESS="✅ Ollama + Open WebUI installed successfully!\n\nDesktop shortcut 'OllamaUI' created.\n\nLaunch it now?"
MSG_FAIL="❌ Installation failed.\n\nSee log: $LOG_FILE"

cat > "$LOG_FILE" << EOF
============================================
 Ollama + Open WebUI — Installation log
 $(date)
 System : $(uname -a)
 Ubuntu : $(lsb_release -d 2>/dev/null | cut -f2)
============================================
EOF

zenity --info --title="Ollama Setup" --text="$MSG_WELCOME" --width=500 2>/dev/null
[ $? -ne 0 ] && exit 0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

check_requirements() {
  log "=== Checking requirements ==="
  local MISSING=""
  local REASONS=""

  if ! grep -q "24.04" /etc/os-release; then
    REASONS="$REASONS\n• Ubuntu 24.04 required (detected: $(lsb_release -d | cut -f2))"
  fi

  [ ! -e /dev/kfd ] && MISSING="$MISSING rocm"
  command -v docker &>/dev/null || MISSING="$MISSING docker"
  command -v curl &>/dev/null || MISSING="$MISSING curl"

  if [ -n "$REASONS" ]; then
    zenity --question --title="⚠️ Incompatibility detected" \
      --text="Issues detected:$REASONS\n\nInstallation may not work.\nCancel?" \
      --ok-label="Cancel" --cancel-label="Continue anyway" --width=500 2>/dev/null
    [ $? -eq 0 ] && exit 0
  fi

  if [ -n "$MISSING" ]; then
    zenity --question --title="Missing requirements" \
      --text="Missing components:\n$MISSING\n\nInstall them automatically via official repositories?" \
      --width=450 2>/dev/null
    [ $? -ne 0 ] && exit 0

    sudo apt update >> "$LOG_FILE" 2>&1
    for dep in $MISSING; do
      case $dep in
        docker)
          sudo apt install -y docker.io >> "$LOG_FILE" 2>&1
          sudo usermod -aG docker $USER >> "$LOG_FILE" 2>&1
          ;;
        curl) sudo apt install -y curl >> "$LOG_FILE" 2>&1 ;;
        rocm)
          log "Installing ROCm..."
          wget -q "https://repo.radeon.com/amdgpu-install/6.3.3/ubuntu/noble/amdgpu-install_6.3.60303-1_all.deb" -O /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
          sudo apt install -y /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
          sudo amdgpu-install --usecase=rocm,hip --no-dkms -y >> "$LOG_FILE" 2>&1
          sudo usermod -aG render,video $USER >> "$LOG_FILE" 2>&1
          echo "REBOOT" > "$STATUS_FILE"
          ;;
      esac
    done

    if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "REBOOT" ]; then
      zenity --question --title="Reboot required" \
        --text="⚠️ ROCm installed. Reboot required.\nReboot now?" \
        --width=400 2>/dev/null
      [ $? -eq 0 ] && sudo reboot
      rm -f "$STATUS_FILE"
      exit 0
    fi
  fi
}

install_ollama_native() {
  log "=== Installing Ollama (native) ==="
  curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Ollama install failed"
    echo "ERROR" > "$STATUS_FILE"
    return 1
  }

  log "Configuring Ollama for AMD GPU..."
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'OVERRIDE'
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=12.0.1"
Environment="OLLAMA_LLM_LIBRARY=rocm"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_HOST=0.0.0.0"
OVERRIDE

  log "=== DISABLING Ollama auto-start at boot (on-demand policy) ==="
  sudo systemctl daemon-reload
  sudo systemctl disable ollama >> "$LOG_FILE" 2>&1
  sudo systemctl stop ollama >> "$LOG_FILE" 2>&1
  log "Ollama will start only when OllamaUI is launched"
}

install_openwebui() {
  log "=== Installing Open WebUI (Docker) ==="
  docker pull ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Open WebUI pull failed"
    echo "ERROR" > "$STATUS_FILE"
    return 1
  }

  # Create the container but DON'T leave it running
  docker stop open-webui 2>/dev/null
  docker rm open-webui 2>/dev/null
  docker create --name open-webui \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1
  log "Open WebUI container created (stopped)"
}

install_scripts() {
  log "=== Installing launch scripts ==="
  cp "$SCRIPT_DIR/ollamaui.sh" "$HOME/"
  cp "$SCRIPT_DIR/stopia.sh" "$HOME/"
  cp "$SCRIPT_DIR/detect_browser.sh" "$HOME/"
  chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"

  DESKTOP="$HOME/Desktop"
  [ ! -d "$DESKTOP" ] && DESKTOP="$HOME/Bureau"

  [ -f "$DESKTOP/OllamaUI.desktop" ] && cp "$DESKTOP/OllamaUI.desktop" "$DESKTOP/OllamaUI.desktop.bak"

  cat > "$DESKTOP/OllamaUI.desktop" << DESK
[Desktop Entry]
Version=1.0
Type=Application
Name=OllamaUI
Comment=Launch Ollama + Open WebUI (on-demand)
Exec=$HOME/ollamaui.sh
Icon=$SCRIPT_DIR/icon.png
Terminal=false
Categories=Application;
DESK
  gio set "$DESKTOP/OllamaUI.desktop" metadata::trusted true 2>/dev/null
  chmod +x "$DESKTOP/OllamaUI.desktop"
}

main_install() {
  check_requirements
  install_ollama_native || return 1
  install_openwebui || return 1
  install_scripts
  log "✅ Installation complete!"
  echo "SUCCESS" > "$STATUS_FILE"
}

main_install &
INSTALL_PID=$!

tail -n 15 -f "$LOG_FILE" 2>/dev/null | zenity --text-info \
  --title="Ollama Setup — Installing..." \
  --width=700 --height=400 --no-wrap \
  --cancel-label="Abort" --ok-label="Close" 2>/dev/null &
ZENITY_PID=$!

while kill -0 $INSTALL_PID 2>/dev/null; do
  if ! kill -0 $ZENITY_PID 2>/dev/null; then
    zenity --question --title="Ollama Setup" --text="Abort installation?" --width=350 2>/dev/null
    if [ $? -eq 0 ]; then
      kill $INSTALL_PID 2>/dev/null
      rm -f "$STATUS_FILE"
      exit 0
    else
      tail -n 15 -f "$LOG_FILE" 2>/dev/null | zenity --text-info \
        --title="Ollama Setup — Installing..." \
        --width=700 --height=400 --no-wrap \
        --cancel-label="Abort" --ok-label="Close" 2>/dev/null &
      ZENITY_PID=$!
    fi
  fi
  sleep 1
done

kill $ZENITY_PID 2>/dev/null

STATUS=$(cat "$STATUS_FILE" 2>/dev/null)
rm -f "$STATUS_FILE"

if [ "$STATUS" = "SUCCESS" ]; then
  zenity --info --title="Ollama Setup" --text="$MSG_SUCCESS" --width=450 2>/dev/null
  echo "Install done — launch from desktop shortcut"
else
  zenity --error --title="Ollama Setup" --text="$MSG_FAIL" \
    --extra-button="View log" --width=450 2>/dev/null
  [ $? -eq 1 ] && zenity --text-info --title="Log" --filename="$LOG_FILE" --width=800 --height=500 2>/dev/null
fi

exit 0
