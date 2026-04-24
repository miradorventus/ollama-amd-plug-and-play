#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Ollama (native) + Open WebUI (Docker) — AMD ROCm
#  Version: 1.4.0
# ============================================================

VERSION="1.4.0"
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
  # Clean up autostart artifacts only. No decorative popup —
  # any zenity window opening here would steal focus from the
  # password prompt that comes next. The script is idempotent:
  # check_requirements will see ROCm installed and skip it.
  rm -f "$AUTOSTART_FILE"
  rm -f "$RESUME_MARKER"
fi

# ============================================================
# Auth — askpass pattern (works with or without TTY)
# ============================================================
# Install a zenity-based askpass helper. When any 'sudo' runs without
# a valid cache (first sudo of the session), sudo spawns this helper
# to ask for the password. Child processes of our script (including
# the sudos inside the official Ollama installer) inherit the cache
# — a single zenity prompt covers the entire install.
ASKPASS_HELPER=$(mktemp --suffix=-ollama-askpass.sh)
cat > "$ASKPASS_HELPER" << 'ASKPASS_EOF'
#!/bin/bash
zenity --password \
  --title="Ollama Setup — Authentication required" \
  --text="Enter your password to install Ollama + Open WebUI:" \
  --width=420 2>/dev/null
ASKPASS_EOF
chmod +x "$ASKPASS_HELPER"
export SUDO_ASKPASS="$ASKPASS_HELPER"

# Prime the sudo cache once. If the user cancels the popup, sudo
# returns non-zero and we bail out cleanly.
if ! sudo -A -v 2>/dev/null; then
  zenity --error --title="Authentication cancelled" \
    --text="❌ Installation cancelled (no password provided)." --width=400 2>/dev/null
  rm -f "$ASKPASS_HELPER"
  exit 1
fi

# Keep sudo cache alive in the background throughout the install.
# Without this, a long step (ROCm download ~2GB) could see the 15min
# cache expire, and a fresh askpass popup would pop up mid-install.
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPER_PID=$!

# Cleanup on exit — kill keeper, remove askpass helper
cleanup_auth() {
  [ -n "$SUDO_KEEPER_PID" ] && kill "$SUDO_KEEPER_PID" 2>/dev/null
  rm -f "$ASKPASS_HELPER"
}
trap cleanup_auth EXIT

MSG_WELCOME="Welcome to the Ollama + Open WebUI installer\n\nThis will install:\n• Ollama (native, via official script)\n• Open WebUI (Docker container)\n\nPOLICY: On-demand only\n• Services start when you launch OllamaUI\n• Services stop when you close the browser\n• Nothing runs at boot — saves power!\n\nRequirements:\n• Ubuntu 24.04\n• AMD GPU with ROCm support\n• Docker (will be installed if missing)\n• ~20 GB free disk space\n\nLog: $LOG_FILE"

cat > "$LOG_FILE" << EOF
============================================
 Ollama + Open WebUI — Installation log
 $(date)
============================================
EOF

zenity --info --title="Ollama Setup" --text="$MSG_WELCOME" --width=500 --timeout=3 2>/dev/null &

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# ============================================================
# STEP 1 — Requirements check (INTERACTIVE, BEFORE progress window)
# ============================================================
log "=== Checking requirements ==="
MISSING=""

if ! dpkg -l 2>/dev/null | grep -q "^ii  rocm-hip-runtime"; then
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
  # Last 7 lines, stripped of timestamps, max 90 chars
  LAST_LINES=$(tail -n 7 "$LOG_FILE" 2>/dev/null | sed 's/^\[[0-9: -]*\] //' | cut -c1-90)
  if [ -n "$LAST_LINES" ]; then
    ESCAPED=$(echo "$LAST_LINES" | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "# $ESCAPED"
  fi
  sleep 1
done
echo "100"
) | zenity --progress \
    --title="Ollama Setup — Installing..." \
    --text="Starting installation..." \
    --pulsate --auto-close \
    --cancel-label="Abort" \
    --width=700 --height=280 2>/dev/null

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
    
    zenity --question --title="Reboot required" \
      --text="⚠️ ROCm was installed — a REBOOT IS REQUIRED to activate it.\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n💾  SAVE YOUR WORK FIRST\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nClose any open documents before continuing.\n\nAfter the reboot (≈ 1–2 min), the installation will resume\nautomatically. You'll see a '✅ Reboot complete!' popup.\n\nReady to reboot now?" \
      --ok-label="Reboot now" --cancel-label="Cancel" \
      --width=500 2>/dev/null
    if [ $? -ne 0 ]; then
      zenity --warning --title="Reboot postponed" \
        --text="⚠️ Installation paused.\n\nTo resume later, reboot manually\nand re-run: ./install_ollama.sh" \
        --width=400 2>/dev/null
      exit 0
    fi
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
