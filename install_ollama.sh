#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Ollama (native) + Open WebUI (Docker) — AMD ROCm
#  Version: 1.2.2
# ============================================================

VERSION="1.2.2"
LOG_FILE="$HOME/install_ollama.log"
STATUS_FILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESUME_MARKER="/tmp/ollama-install-resume"
AUTOSTART_FILE="$HOME/.config/autostart/ollama-install-resume.desktop"

if ! command -v zenity &>/dev/null; then
  sudo apt install zenity -y
fi

# ============================================================
# POST-REBOOT RESUME
# ============================================================
if [ "$1" = "--resume" ] || [ -f "$RESUME_MARKER" ]; then
  rm -f "$AUTOSTART_FILE"
  rm -f "$RESUME_MARKER"
  zenity --info --title="Ollama Setup — Resuming" \
    --text="✅ Reboot complete!\nContinuing installation..." \
    --width=400 --timeout=3 2>/dev/null
  SKIP_ROCM=1
fi

# ============================================================
# Auth
# ============================================================
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

cat > "$LOG_FILE" << EOF
============================================
 Ollama + Open WebUI — Installation log
 $(date)
============================================
EOF

if [ -z "$SKIP_ROCM" ]; then
  zenity --info --title="Ollama Setup" --text="$MSG_WELCOME" --width=500 2>/dev/null
  [ $? -ne 0 ] && exit 0
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# ============================================================
# STEP 1 — Requirements check (INTERACTIVE, BEFORE progress window)
# ============================================================
log "=== Checking requirements ==="
MISSING=""

if [ -z "$SKIP_ROCM" ] && ! dpkg -l 2>/dev/null | grep -q "^ii  rocm-hip-runtime"; then
  MISSING="$MISSING rocm"
fi
command -v docker &>/dev/null || MISSING="$MISSING docker"
command -v curl &>/dev/null || MISSING="$MISSING curl"

if [ -n "$MISSING" ]; then
  zenity --question --modal --title="Missing requirements" \
    --text="Missing components:\n$MISSING\n\nInstall them automatically via official repositories?" \
    --width=450 2>/dev/null
  if [ $? -ne 0 ]; then
    zenity --warning --title="Installation cancelled" \
      --text="⚠️ Installation cancelled by user." --width=350 2>/dev/null
    exit 0
  fi
  INSTALL_DEPS=1
else
  INSTALL_DEPS=0
fi

# ============================================================
# STEP 2 — Install dependencies (with progress window)
# ============================================================
install_deps() {
  if [ "$INSTALL_DEPS" = "1" ]; then
    log "Installing missing dependencies: $MISSING"
    sudo apt update >> "$LOG_FILE" 2>&1
    
    for dep in $MISSING; do
      case $dep in
        docker)
          log "Installing Docker..."
          sudo apt install -y docker.io >> "$LOG_FILE" 2>&1
          sudo usermod -aG docker $USER >> "$LOG_FILE" 2>&1
          ;;
        curl)
          log "Installing curl..."
          sudo apt install -y curl >> "$LOG_FILE" 2>&1
          ;;
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
  fi
}

install_ollama_native() {
  log "=== Installing Ollama (native) ==="
  curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
  # Official script may return non-zero even on success (e.g. 'ollama' group already exists).
  # Check the actual binary instead of the exit code.
  if ! command -v ollama &>/dev/null; then
    log "ERROR: Ollama install failed (binary not found)"
    echo "ERROR" > "$STATUS_FILE"
    return 1
  fi

  log "Configuring Ollama for AMD GPU..."
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'OVERRIDE'
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=12.0.1"
Environment="OLLAMA_LLM_LIBRARY=rocm"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_HOST=0.0.0.0"
OVERRIDE

  log "Setting up NOPASSWD for stop only..."
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ollama, /usr/bin/systemctl stop ollama.service" | sudo tee /etc/sudoers.d/ollama-nopasswd-stop > /dev/null
  sudo chmod 440 /etc/sudoers.d/ollama-nopasswd-stop

  log "Disabling Ollama auto-start at boot..."
  sudo systemctl daemon-reload
  sudo systemctl disable ollama >> "$LOG_FILE" 2>&1
  sudo systemctl stop ollama >> "$LOG_FILE" 2>&1
}

install_openwebui() {
  log "=== Installing Open WebUI (Docker) ==="
  docker pull ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Open WebUI pull failed"
    echo "ERROR" > "$STATUS_FILE"
    return 1
  }

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
  [ ! -d "$DESKTOP" ] && mkdir -p "$DESKTOP"

  [ -f "$DESKTOP/OllamaUI.desktop" ] && cp "$DESKTOP/OllamaUI.desktop" "$DESKTOP/OllamaUI.desktop.bak"

  ICON_PATH="$SCRIPT_DIR/icon.png"
  [ ! -f "$ICON_PATH" ] && ICON_PATH="utilities-terminal"

  cat > "$DESKTOP/OllamaUI.desktop" << DESK
[Desktop Entry]
Version=1.0
Type=Application
Name=OllamaUI
Comment=Launch Ollama + Open WebUI (on-demand)
Exec=$HOME/ollamaui.sh
Icon=$ICON_PATH
Terminal=false
Categories=Application;
DESK
  gio set "$DESKTOP/OllamaUI.desktop" metadata::trusted true 2>/dev/null
  chmod +x "$DESKTOP/OllamaUI.desktop"
  log "Desktop shortcut created at $DESKTOP/OllamaUI.desktop"
}

# ============================================================
# STEP 3 — Run installation (background) + progress window
# ============================================================
run_install() {
  install_deps
  
  # Check if reboot needed
  if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "REBOOT" ]; then
    return 0  # Will handle reboot AFTER progress window closes
  fi
  
  install_ollama_native || return 1
  install_openwebui || return 1
  install_scripts
  log "✅ Installation complete!"
  echo "SUCCESS" > "$STATUS_FILE"
}

run_install &
MAIN_PID=$!

# Progress window with last-line display
(
while kill -0 $MAIN_PID 2>/dev/null; do
  LAST_LINE=$(tail -n 1 "$LOG_FILE" 2>/dev/null | sed 's/^\[[0-9: -]*\] //' | cut -c1-80)
  [ -n "$LAST_LINE" ] && echo "# $LAST_LINE"
  sleep 1
done
echo "100"
) | zenity --progress \
    --title="Ollama Setup — Installing..." \
    --text="Starting installation..." \
    --pulsate --auto-close \
    --cancel-label="Abort" \
    --width=600 2>/dev/null

# Check if zenity was cancelled
if [ $? -ne 0 ] && kill -0 $MAIN_PID 2>/dev/null; then
  kill $MAIN_PID 2>/dev/null
  # Kill any child processes too
  pkill -P $MAIN_PID 2>/dev/null
  echo "ABORTED" > "$STATUS_FILE"
fi

wait $MAIN_PID 2>/dev/null

STATUS=$(cat "$STATUS_FILE" 2>/dev/null)
rm -f "$STATUS_FILE"

# ============================================================
# STEP 4 — Handle result
# ============================================================
case "$STATUS" in
  SUCCESS)
    zenity --question --title="Ollama Setup" \
      --text="✅ Ollama + Open WebUI installed successfully!\n\nDesktop shortcut 'OllamaUI' created.\n\nLaunch it now?" \
      --ok-label="Launch now" --cancel-label="Later" \
      --width=450 2>/dev/null
    if [ $? -eq 0 ]; then
      log "Launching OllamaUI from installer..."
      nohup "$HOME/ollamaui.sh" >/dev/null 2>&1 &
      disown
    fi
    ;;
  REBOOT)
    # Setup resume on next boot
    log "Setting up post-reboot resume..."
    touch "$RESUME_MARKER"
    mkdir -p "$HOME/.config/autostart"
    cat > "$AUTOSTART_FILE" << AUTOEOF
[Desktop Entry]
Type=Application
Name=Ollama Install Resume
Exec=bash -c "$SCRIPT_DIR/install_ollama.sh --resume"
X-GNOME-Autostart-enabled=true
AUTOEOF
    chmod +x "$AUTOSTART_FILE"
    
    zenity --info --title="Reboot required" \
      --text="⚠️ ROCm installed. A reboot is required.\n\nAfter the reboot, the installation will automatically continue.\n\nClick OK to reboot now." \
      --width=450 2>/dev/null
    sudo reboot
    ;;
  ABORTED)
    zenity --warning --title="Installation aborted" \
      --text="⚠️ Installation was aborted.\nRun the installer again anytime." \
      --width=400 2>/dev/null
    ;;
  *)
    zenity --error --title="Ollama Setup" \
      --text="❌ Installation failed.\n\nSee log: $LOG_FILE" \
      --extra-button="View log" --width=450 2>/dev/null
    [ $? -eq 1 ] && zenity --text-info --title="Log" --filename="$LOG_FILE" --width=800 --height=500 2>/dev/null
    ;;
esac

exit 0
