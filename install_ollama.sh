#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Ollama (native) + Open WebUI (Docker) — AMD ROCm
#  Version: 1.0.0
# ============================================================
#  Sources used (all official):
#    • Ollama:    https://ollama.com/install.sh
#    • WebUI:     ghcr.io/open-webui/open-webui (GitHub)
#    • ROCm:      https://repo.radeon.com (AMD)
#    • Docker:    Ubuntu/Mint apt repos
# ============================================================

VERSION="2.0.1"
REPO_URL="https://github.com/miradorventus/ollama-amd-plug-and-play"
DEFAULT_OLLAMAUI_DIR="$HOME/.ollamaui"
OLLAMAUI_DIR="$DEFAULT_OLLAMAUI_DIR"
CUSTOM_PARENT=""
STATUS_FILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_FILE="$HOME/.config/autostart/ollama-install-resume.desktop"
LOG_FILE=""

TRACK_FILE=$(mktemp --suffix=-ollama-track)
track() { echo "$1" >> "$TRACK_FILE"; }
was_done() { grep -q "^$1$" "$TRACK_FILE" 2>/dev/null; }

command -v zenity &>/dev/null || sudo apt install -y zenity
rm -f "$AUTOSTART_FILE"

ASKPASS_HELPER=$(mktemp --suffix=-ollama-askpass.sh)
cat > "$ASKPASS_HELPER" << 'ASKPASS_EOF'
#!/bin/bash
zenity --password \
  --title="Ollama Setup — Authentication" \
  --text="Enter your password to install Ollama + Open WebUI:" \
  --width=420 2>/dev/null
ASKPASS_EOF
chmod +x "$ASKPASS_HELPER"
export SUDO_ASKPASS="$ASKPASS_HELPER"

cleanup_auth() {
  [ -n "$SUDO_KEEPER_PID" ] && kill "$SUDO_KEEPER_PID" 2>/dev/null
  rm -f "$ASKPASS_HELPER" "$STATUS_FILE" "$TRACK_FILE"
}

rollback() {
  log "=== ROLLBACK started ==="
  was_done "shortcut" && {
    rm -f "$HOME/Bureau/OllamaUI.desktop" "$HOME/Desktop/OllamaUI.desktop" 2>/dev/null
    log "  Removed desktop shortcut"
  }
  was_done "scripts" && {
    rm -f "$OLLAMAUI_DIR/ollamaui-launcher.sh" "$OLLAMAUI_DIR/stopia.sh" "$OLLAMAUI_DIR/detect_browser.sh"
    rm -f "$OLLAMAUI_DIR/ollamaui.sh"
    rm -f "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"
    log "  Removed launch scripts"
  }
  was_done "symlink" && {
    [ -n "$CUSTOM_PARENT" ] && rm -f "$CUSTOM_PARENT/ollama-models" 2>/dev/null
    log "  Removed ollama-models symlink"
  }
  was_done "ufw" && {
    sudo -n ufw delete allow from 172.17.0.0/16 to any port 11434 proto tcp 2>/dev/null
    log "  Removed UFW rule"
  }
  was_done "webui" && {
    docker stop open-webui 2>/dev/null
    docker rm open-webui 2>/dev/null
    log "  Removed Open WebUI container (volume preserved)"
  }
  was_done "ollama_systemd" && {
    sudo -n rm -f /etc/sudoers.d/ollama-nopasswd-stop
    sudo -n rm -rf /etc/systemd/system/ollama.service.d
    sudo -n systemctl daemon-reload 2>/dev/null
    log "  Removed Ollama systemd config + sudoers"
  }
  was_done "ollama_binary" && {
    sudo -n systemctl stop ollama 2>/dev/null
    sudo -n systemctl disable ollama 2>/dev/null
    sudo -n rm -rf /etc/systemd/system/ollama.service
    sudo -n rm -f /usr/local/bin/ollama
    sudo -n rm -rf /usr/share/ollama /usr/local/lib/ollama
    sudo -n userdel ollama 2>/dev/null
    sudo -n groupdel ollama 2>/dev/null
    log "  Removed Ollama binary + user/group"
  }
  log "=== ROLLBACK done ==="
}

cleanup_full() { cleanup_auth; }
trap cleanup_full EXIT

confirm_stop_and_exit() {
  local items=""
  was_done "ollama_binary"   && items+="  • Ollama binary + service\n"
  was_done "ollama_systemd"  && items+="  • Ollama systemd config + sudoers\n"
  was_done "webui"           && items+="  • Open WebUI container\n"
  was_done "ufw"             && items+="  • UFW firewall rule\n"
  was_done "scripts"         && items+="  • Launch scripts\n"
  was_done "shortcut"        && items+="  • Desktop shortcut\n"
  was_done "symlink"         && items+="  • ollama-models symlink\n"
  
  local kept=""
  was_done "rocm" && kept+="  • ROCm 7.2.2 (10 GB) — to remove:\n      sudo apt remove --purge 'rocm-*' 'hip-*'\n      sudo apt autoremove\n"
  was_done "webui" && kept+="  • Open WebUI conversations volume (preserved)\n      To remove: docker volume rm open-webui\n"
  
  local msg="⚠️ Stop installation?\n\n"
  if [ -n "$items" ]; then
    msg+="Will be removed:\n$items\n"
  else
    msg+="Nothing was installed yet — clean exit.\n\n"
  fi
  if [ -n "$kept" ]; then
    msg+="NOT removed (manual cleanup if needed):\n$kept"
  fi
  
  zenity --question --title="Confirm stop" \
    --text="$msg" \
    --ok-label="❌ Yes, stop and rollback" \
    --cancel-label="✅ Cancel — keep installing" \
    --width=550 2>/dev/null
  
  if [ $? -eq 0 ]; then
    rollback
    log "User confirmed stop. Rollback done."
    exit 0
  fi
  return 1
}

# ─── PRE-CHECK (silent, sets globals) ───────────────────────
PRE_CHECK_OS_OK=0
OS_NAME="Unknown"
if [ -f /etc/os-release ]; then
  OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
  if grep -qE '^ID=(ubuntu|linuxmint)' /etc/os-release || \
     grep -qE '^ID_LIKE=.*ubuntu' /etc/os-release; then
    PRE_CHECK_OS_OK=1
  fi
fi

PRE_CHECK_ROCM=0
dpkg -l 2>/dev/null | grep -q "^ii  rocm-hip-runtime" && PRE_CHECK_ROCM=1
PRE_CHECK_DOCKER=0
command -v docker &>/dev/null && PRE_CHECK_DOCKER=1
PRE_CHECK_CURL=0
command -v curl &>/dev/null && PRE_CHECK_CURL=1
PRE_CHECK_OLLAMA=0
command -v ollama &>/dev/null && PRE_CHECK_OLLAMA=1
PRE_CHECK_OLLAMA_ENABLED=0
systemctl is-enabled ollama 2>/dev/null | grep -q "^enabled$" && PRE_CHECK_OLLAMA_ENABLED=1
PRE_CHECK_WEBUI=0
docker ps -a --filter name=open-webui --format "{{.Names}}" 2>/dev/null | grep -q open-webui && PRE_CHECK_WEBUI=1
PRE_CHECK_UFW_ACTIVE=0
if command -v ufw &>/dev/null; then
  sudo -n ufw status 2>/dev/null | head -1 | grep -qiE "active|actif" && PRE_CHECK_UFW_ACTIVE=1
fi
PRE_CHECK_SHORTCUT=0
for d in "$HOME/Desktop" "$HOME/Bureau"; do
  [ -f "$d/OllamaUI.desktop" ] && PRE_CHECK_SHORTCUT=1
done

# ─── Build welcome message ──────────────────────────────────
WELCOME="Welcome to the Ollama + Open WebUI installer\n\n"
WELCOME+="Detected on your system:\n"
[ "$PRE_CHECK_OS_OK" = "1" ] && WELCOME+="  ✅ $OS_NAME\n" || WELCOME+="  ⚠️ $OS_NAME (untested)\n"
[ "$PRE_CHECK_CURL" = "1" ]   && WELCOME+="  ✅ curl\n"          || WELCOME+="  ⬜ curl — will install\n"
[ "$PRE_CHECK_DOCKER" = "1" ] && WELCOME+="  ✅ Docker\n"        || WELCOME+="  ⬜ Docker — will install (~50 MB)\n"

TOTAL_DL=0
REBOOT_NEEDED=0
if [ "$PRE_CHECK_ROCM" = "1" ]; then
  WELCOME+="  ✅ ROCm 7.2.2\n"
else
  WELCOME+="  ⬜ ROCm 7.2.2 — will install from repo.radeon.com (~10 GB)\n"
  TOTAL_DL=$((TOTAL_DL + 10000))
  REBOOT_NEEDED=1
fi
[ "$PRE_CHECK_OLLAMA" = "1" ] && WELCOME+="  ✅ Ollama (will be reused)\n" || { WELCOME+="  ⬜ Ollama — will install from ollama.com (~1.5 GB)\n"; TOTAL_DL=$((TOTAL_DL + 1500)); }
[ "$PRE_CHECK_WEBUI" = "1" ]  && WELCOME+="  ✅ Open WebUI (will be reused)\n" || { WELCOME+="  ⬜ Open WebUI — will install from ghcr.io (~1.5 GB)\n"; TOTAL_DL=$((TOTAL_DL + 1500)); }
[ "$PRE_CHECK_SHORTCUT" = "1" ] && WELCOME+="  ✅ Desktop shortcut 'OllamaUI'\n\n" || WELCOME+="  ⬜ Desktop shortcut 'OllamaUI'\n\n"

WELCOME+="Total download: ~$((TOTAL_DL / 1000)) GB\n"
[ "$REBOOT_NEEDED" = "1" ] && WELCOME+="Reboot required: YES (after ROCm install)\n" || WELCOME+="Reboot required: NO\n"
WELCOME+="\nPOLICY: On-demand only\n"
WELCOME+="• Services start when you launch OllamaUI\n"
WELCOME+="• Services stop when you close the browser\n"
WELCOME+="• Nothing runs at boot — saves power!\n"

# ============================================================
# WELCOME ↔ INSTALL LOCATION (state machine, Back supported)
# ============================================================
STATE="welcome"
while true; do
  case "$STATE" in
    welcome)
      zenity --question --title="Ollama Setup" --text="$WELCOME" \
        --ok-label="✅ Continue" --cancel-label="❌ Cancel" \
        --width=550 2>/dev/null
      [ $? -ne 0 ] && exit 0
      STATE="install_location"
      ;;
    
    install_location)
      LOC_MSG="📁 Where to install OllamaUI?\n\n"
      LOC_MSG+="Default location:\n"
      LOC_MSG+="  ~/.ollamaui/   (hidden, standard Linux convention)\n\n"
      LOC_MSG+="Or choose a custom parent folder where we'll create:\n"
      LOC_MSG+="  <your-folder>/ollamaui/   (scripts)\n"
      LOC_MSG+="  <your-folder>/ollama-models   (symlink → real models folder)\n\n"
      LOC_MSG+="Note: the symlink is just a shortcut to the actual\n"
      LOC_MSG+="model storage at /usr/share/ollama/.ollama/models\n"
      LOC_MSG+="You can drag-and-drop .gguf files, delete models, etc.\n"
      LOC_MSG+="from your file manager."
      
      LOC_RES=$(zenity --question --title="Install location" --text="$LOC_MSG" \
        --ok-label="✅ Default" --cancel-label="← Back" \
        --extra-button="📁 Custom location" \
        --width=580 2>/dev/null)
      LOC_CODE=$?
      
      if [ "$LOC_RES" = "📁 Custom location" ]; then
        # File picker for parent folder (must exist)
        CUSTOM_PARENT=$(zenity --file-selection --directory \
          --title="Choose parent folder for OllamaUI" \
          --filename="$HOME/" 2>/dev/null)
        if [ -z "$CUSTOM_PARENT" ]; then
          STATE="install_location"
          continue
        fi
        if [ ! -d "$CUSTOM_PARENT" ]; then
          zenity --warning --title="Invalid folder" \
            --text="The selected folder doesn't exist:\n$CUSTOM_PARENT" \
            --width=400 2>/dev/null
          STATE="install_location"
          continue
        fi
        OLLAMAUI_DIR="$CUSTOM_PARENT/ollamaui"
        mkdir -p "$OLLAMAUI_DIR"
        STATE="proceed"
      elif [ $LOC_CODE -eq 0 ]; then
        OLLAMAUI_DIR="$DEFAULT_OLLAMAUI_DIR"
        mkdir -p "$OLLAMAUI_DIR"
        STATE="proceed"
      else
        STATE="welcome"
      fi
      ;;
    
    proceed)
      break
      ;;
  esac
done

# Set log file path now that OLLAMAUI_DIR is finalized
LOG_FILE="$OLLAMAUI_DIR/install_ollama.log"

cat > "$LOG_FILE" << LOG_EOF
============================================
 Ollama + Open WebUI — Installation log
 $(date)
 Version: $VERSION
 Install dir: $OLLAMAUI_DIR
LOG_EOF
[ -n "$CUSTOM_PARENT" ] && echo " Custom parent: $CUSTOM_PARENT" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
log "=== Pre-check ==="
log "Pre-check: OS=$OS_NAME ROCm=$PRE_CHECK_ROCM Docker=$PRE_CHECK_DOCKER Curl=$PRE_CHECK_CURL Ollama=$PRE_CHECK_OLLAMA OllamaEnabled=$PRE_CHECK_OLLAMA_ENABLED WebUI=$PRE_CHECK_WEBUI UFWActive=$PRE_CHECK_UFW_ACTIVE Shortcut=$PRE_CHECK_SHORTCUT"
log "Install dir: $OLLAMAUI_DIR"

for old_file in ollamaui.sh stopia.sh detect_browser.sh install_ollama.log ollamaui.log; do
  if [ -f "$HOME/$old_file" ] && [ ! -f "$OLLAMAUI_DIR/$old_file" ]; then
    mv "$HOME/$old_file" "$OLLAMAUI_DIR/$old_file" 2>/dev/null
  fi
done

if [ -f "$OLLAMAUI_DIR/ollamaui.sh" ] && [ ! -f "$OLLAMAUI_DIR/ollamaui-launcher.sh" ]; then
  mv "$OLLAMAUI_DIR/ollamaui.sh" "$OLLAMAUI_DIR/ollamaui-launcher.sh" 2>/dev/null
fi

log "Authenticating..."
if ! sudo -A -v 2>/dev/null; then
  zenity --error --title="Authentication cancelled" \
    --text="❌ Installation cancelled (no password)." --width=400 2>/dev/null
  exit 1
fi
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPER_PID=$!

run_with_progress() {
  local title="$1"
  shift
  ( "$@" ) &
  local pid=$!
  (
    while kill -0 $pid 2>/dev/null; do
      LAST_LINES=$(tail -n 7 "$LOG_FILE" 2>/dev/null | sed 's/^\[[0-9: -]*\] //' | cut -c1-90)
      ESCAPED=$(echo "$LAST_LINES" | sed ':a;N;$!ba;s/\n/\\n/g')
      [ -n "$ESCAPED" ] && echo "# $ESCAPED"
      sleep 1
    done
    echo "100"
  ) | zenity --progress --title="$title" --text="Working..." \
      --pulsate --auto-close --no-cancel \
      --width=700 --height=280 2>/dev/null
  wait $pid
  return $?
}

# ============================================================
#  STEP 1/3 — DEPENDENCIES
# ============================================================
MISSING=""
[ "$PRE_CHECK_ROCM" = "0" ]   && MISSING="$MISSING rocm"
[ "$PRE_CHECK_DOCKER" = "0" ] && MISSING="$MISSING docker"
[ "$PRE_CHECK_CURL" = "0" ]   && MISSING="$MISSING curl"

if [ -n "$MISSING" ]; then
  STEP1_MSG="Step 1/3 — Install dependencies\n\n"
  STEP1_MSG+="Source: official repos\n"
  for dep in $MISSING; do
    case $dep in
      rocm)   STEP1_MSG+="  • ROCm 7.2.2 (repo.radeon.com)\n" ;;
      docker) STEP1_MSG+="  • Docker (Ubuntu/Mint apt repos)\n" ;;
      curl)   STEP1_MSG+="  • curl (Ubuntu/Mint apt repos)\n" ;;
    esac
  done
  STEP1_MSG+="\nAction: system packages, group memberships"
  [ "$PRE_CHECK_ROCM" = "0" ] && STEP1_MSG+="\nReboot required: YES (after ROCm install)"
  
  zenity --question --title="Step 1/3 — Dependencies" --text="$STEP1_MSG" \
    --ok-label="✅ Install" --cancel-label="❌ Stop install" \
    --width=500 2>/dev/null
  if [ $? -ne 0 ]; then
    confirm_stop_and_exit
    log "User cancelled step 1 but kept install — skipping deps"
  else
    log "=== Step 1/3 — Installing dependencies ==="
    install_deps_fn() {
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
            log "Installing ROCm 7.2.2..."
            sudo mkdir -p --mode=0755 /etc/apt/keyrings
            wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
            # Repos officiels ROCm 7.2.2 (selon doc AMD)
            sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null << 'ROCMREPO_EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2.1/ubuntu noble main
ROCMREPO_EOF
            # Pin priority pour préférer ces repos officiels (selon doc AMD)
            sudo tee /etc/apt/preferences.d/rocm-pin-600 > /dev/null << 'ROCMPIN_EOF'
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
ROCMPIN_EOF
            wget -q "https://repo.radeon.com/amdgpu-install/7.2.2/ubuntu/noble/amdgpu-install_7.2.2.70202-1_all.deb" -O /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
            sudo apt install --reinstall -y /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
            # Fix AMD repo bug: amdgpu-install écrit graphics/7.2.2 qui n'existe pas → corriger en 7.2.1
            sudo sed -i 's|graphics/7.2.2|graphics/7.2.1|g' /etc/apt/sources.list.d/rocm.list 2>/dev/null
            sudo apt update >> "$LOG_FILE" 2>&1
            sudo amdgpu-install --usecase=rocm,hip --no-dkms -y >> "$LOG_FILE" 2>&1
            sudo usermod -aG render,video $USER >> "$LOG_FILE" 2>&1
            if dpkg -l | grep -q "^ii  rocm-hip-runtime"; then
              log "✅ ROCm 7.2.2 installed successfully"
              track "rocm"
              echo "REBOOT" > "$STATUS_FILE"
            else
              log "❌ ERROR: ROCm install failed"
              echo "ERROR" > "$STATUS_FILE"
              return 1
            fi
            ;;
        esac
      done
    }
    run_with_progress "Step 1/3 — Installing dependencies..." install_deps_fn
    if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "ERROR" ]; then
      zenity --error --title="Step 1/3 failed" \
        --text="❌ Failed to install ROCm.\n\nCheck the log: $LOG_FILE" --width=450 2>/dev/null
      exit 1
    fi
    log "Step 1/3 done"
  fi
fi

if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "REBOOT" ]; then
  log "Reboot required after ROCm install"
  mkdir -p "$HOME/.config/autostart"
  cat > "$AUTOSTART_FILE" << AUTOEOF
[Desktop Entry]
Type=Application
Name=Ollama Install Resume
Exec=bash -c "$SCRIPT_DIR/install_ollama.sh"
X-GNOME-Autostart-enabled=true
AUTOEOF
  chmod +x "$AUTOSTART_FILE"
  
  zenity --question --title="Reboot required" \
    --text="⚠️ ROCm was installed — REBOOT REQUIRED to activate it.\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n💾 SAVE YOUR WORK FIRST\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nAfter the reboot (~1-2 min), the installation will\nresume automatically and complete.\n\nReady to reboot now?" \
    --ok-label="✅ Reboot now" --cancel-label="❌ Cancel" \
    --width=500 2>/dev/null
  if [ $? -ne 0 ]; then
    rm -f "$AUTOSTART_FILE"
    log "User cancelled reboot — install paused"
    zenity --info --title="Install paused" \
      --text="Installation paused.\n\nReboot manually and re-run install_ollama.sh\nto resume." \
      --width=420 2>/dev/null
    exit 0
  fi
  log "Rebooting..."
  sudo reboot
  exit 0
fi

# ============================================================
#  STEP 2/3 — OLLAMA
# ============================================================
if [ "$PRE_CHECK_OLLAMA" = "0" ]; then
  STEP2_MSG="Step 2/3 — Install Ollama\n\n"
  STEP2_MSG+="Source: official ollama.com installer\n\n"
  STEP2_MSG+="Choose:\n"
  STEP2_MSG+="  • Install fresh — clean install (~1.5 GB)\n"
  STEP2_MSG+="  • Import existing — point to your Ollama folder\n"
  STEP2_MSG+="  • Stop install — abort the installer"
  
  STEP2_RES=$(zenity --question --title="Step 2/3 — Ollama" --text="$STEP2_MSG" \
    --ok-label="✅ Install fresh" --cancel-label="❌ Stop install" \
    --extra-button="Import existing" \
    --width=500 2>/dev/null)
  STEP2_CODE=$?
  
  OLLAMA_MODELS_PATH=""
  if [ "$STEP2_RES" = "Import existing" ]; then
    while true; do
      OLLAMA_MODELS_PATH=$(zenity --file-selection --directory \
        --title="Select your existing Ollama folder" \
        --filename="$HOME/.ollama/" 2>/dev/null)
      if [ -z "$OLLAMA_MODELS_PATH" ]; then
        OLLAMA_MODELS_PATH=""
        STEP2_CODE=0
        break
      fi
      if [ -d "$OLLAMA_MODELS_PATH/models" ] || [ -d "$OLLAMA_MODELS_PATH/blobs" ] || \
         [ -d "$OLLAMA_MODELS_PATH/manifests" ]; then
        STEP2_CODE=0
        break
      else
        zenity --question --title="Not a valid Ollama folder" \
          --text="The folder does not look like an Ollama data folder.\n\nA valid Ollama folder contains:\n  • models/  or  blobs/  or  manifests/" \
          --ok-label="Try another folder" --cancel-label="Install fresh instead" \
          --width=500 2>/dev/null
        if [ $? -ne 0 ]; then
          OLLAMA_MODELS_PATH=""
          STEP2_CODE=0
          break
        fi
      fi
    done
  elif [ $STEP2_CODE -ne 0 ]; then
    confirm_stop_and_exit
  fi
  
  log "=== Step 2/3 — Setting up Ollama ==="
  install_ollama_fn() {
    log "Installing Ollama binary from ollama.com..."
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    if ! command -v ollama &>/dev/null; then
      log "ERROR: Ollama install failed (binary not found)"
      echo "ERROR" > "$STATUS_FILE"
      return 1
    fi
    track "ollama_binary"
    [ -n "$OLLAMA_MODELS_PATH" ] && log "Will configure Ollama to use existing models at: $OLLAMA_MODELS_PATH"
    
    log "Configuring systemd override (merge with existing)..."
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    
    EXISTING_OVERRIDE=""
    [ -f /etc/systemd/system/ollama.service.d/override.conf ] && \
      EXISTING_OVERRIDE=$(sudo cat /etc/systemd/system/ollama.service.d/override.conf)
    
    NEW_OVERRIDE="[Service]"
    
    declare -A REQUIRED=( \
      ["HSA_OVERRIDE_GFX_VERSION"]="12.0.1" \
      ["OLLAMA_LLM_LIBRARY"]="rocm" \
      ["OLLAMA_KEEP_ALIVE"]="5m" \
    )
    REQUIRED["OLLAMA_HOST"]="172.17.0.1"
    [ -n "$OLLAMA_MODELS_PATH" ] && REQUIRED["OLLAMA_MODELS"]="$OLLAMA_MODELS_PATH"
    
    for key in "${!REQUIRED[@]}"; do
      USER_VAL=$(echo "$EXISTING_OVERRIDE" | grep -oP "Environment=\"$key=\K[^\"]+" | head -1)
      if [ "$key" = "OLLAMA_HOST" ]; then
        NEW_OVERRIDE+="\nEnvironment=\"$key=${REQUIRED[$key]}\""
      elif [ -n "$USER_VAL" ]; then
        NEW_OVERRIDE+="\nEnvironment=\"$key=$USER_VAL\""
      else
        NEW_OVERRIDE+="\nEnvironment=\"$key=${REQUIRED[$key]}\""
      fi
    done
    
    echo -e "$NEW_OVERRIDE" | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
    track "ollama_systemd"
    
    log "Setting up NOPASSWD stop..."
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ollama, /usr/bin/systemctl stop ollama.service" | \
      sudo tee /etc/sudoers.d/ollama-nopasswd-stop > /dev/null
    sudo chmod 440 /etc/sudoers.d/ollama-nopasswd-stop
    
    sudo systemctl daemon-reload
    
    if [ "$PRE_CHECK_OLLAMA_ENABLED" = "1" ]; then
      log "Ollama was already enabled — keeping user's preference"
    else
      log "Disabling Ollama auto-start (on-demand policy)..."
      sudo systemctl disable ollama >> "$LOG_FILE" 2>&1
      sudo systemctl stop ollama >> "$LOG_FILE" 2>&1
    fi
    
    log "Configuring models folder permissions for user access..."
    sudo usermod -aG ollama $USER >> "$LOG_FILE" 2>&1
    if [ -d /usr/share/ollama/.ollama/models ]; then
      sudo chmod -R g+w /usr/share/ollama/.ollama/models 2>>"$LOG_FILE"
      sudo chmod g+s /usr/share/ollama/.ollama/models 2>>"$LOG_FILE"
      log "✅ User added to ollama group, models folder writable by group (setgid)"
    fi
  }
  run_with_progress "Step 2/3 — Setting up Ollama..." install_ollama_fn
  if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "ERROR" ]; then
    zenity --error --title="Ollama install failed" \
      --text="❌ Failed to install Ollama.\n\nSee log: $LOG_FILE" --width=400 2>/dev/null
    exit 1
  fi
  log "Step 2/3 done"
fi

# ============================================================
#  STEP 3/3 — OPEN WEBUI + FINALIZE
# ============================================================
WEBUI_MODE="install"
WEBUI_EXTERNAL_URL=""

if [ "$PRE_CHECK_WEBUI" = "0" ]; then
  STEP3_MSG="Step 3/3 — Open WebUI\n\n"
  STEP3_MSG+="Source: official ghcr.io/open-webui\n\n"
  STEP3_MSG+="Choose:\n"
  STEP3_MSG+="  • Install fresh — install in Docker (~1.5 GB)\n"
  STEP3_MSG+="  • I have it elsewhere — give us your URL\n"
  STEP3_MSG+="  • Stop install — abort the installer"
  
  STEP3_RES=$(zenity --question --title="Step 3/3 — Open WebUI" --text="$STEP3_MSG" \
    --ok-label="✅ Install fresh" --cancel-label="❌ Stop install" \
    --extra-button="I have it elsewhere" \
    --width=500 2>/dev/null)
  STEP3_CODE=$?
  
  if [ "$STEP3_RES" = "I have it elsewhere" ]; then
    WEBUI_EXTERNAL_URL=$(zenity --entry --title="Your Open WebUI URL" \
      --text="You already have Open WebUI running. Great!\n\nPaste its URL below.\n\nExamples:\n  http://127.0.0.1:3000\n  http://192.168.1.50:3000\n  http://localhost:8080\n\nURL:" \
      --width=520 2>/dev/null)
    if [ -z "$WEBUI_EXTERNAL_URL" ]; then
      WEBUI_MODE="install"
    else
      WEBUI_MODE="external"
      log "External WebUI URL: $WEBUI_EXTERNAL_URL"
    fi
  elif [ $STEP3_CODE -ne 0 ]; then
    confirm_stop_and_exit
  fi
fi

if [ "$WEBUI_MODE" = "install" ] && [ "$PRE_CHECK_WEBUI" = "0" ]; then
  log "=== Step 3/3 — Installing Open WebUI ==="
  install_webui_fn() {
    docker pull ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1 || {
      log "ERROR: WebUI pull failed"
      echo "ERROR" > "$STATUS_FILE"
      return 1
    }
    docker stop open-webui 2>/dev/null
    docker rm open-webui 2>/dev/null
    docker create --name open-webui \
      -p 127.0.0.1:3000:8080 \
      --add-host=host.docker.internal:host-gateway \
      -v open-webui:/app/backend/data \
      ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1
    track "webui"
    log "WebUI container created"
  }
  run_with_progress "Step 3/3 — Installing Open WebUI..." install_webui_fn
  if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "ERROR" ]; then
    zenity --error --title="WebUI install failed" \
      --text="❌ Failed to install Open WebUI.\n\nSee log: $LOG_FILE" --width=400 2>/dev/null
    exit 1
  fi
fi

# UFW rule
if command -v ufw &>/dev/null && \
   sudo ufw status 2>/dev/null | head -1 | grep -qiE "active|actif"; then
  log "UFW is active — adding rule for Docker subnet → port 11434"
  sudo ufw allow from 172.17.0.0/16 to any port 11434 proto tcp comment 'Ollama for Docker containers' 2>/dev/null
  sudo ufw reload 2>/dev/null
  track "ufw"
else
  log "UFW not active — no firewall rule needed"
fi

# Install scripts (verify source files exist BEFORE copy)
log "Installing launch scripts to $OLLAMAUI_DIR..."
for SRC_FILE in ollamaui-launcher.sh stopia.sh detect_browser.sh; do
  if [ ! -f "$SCRIPT_DIR/$SRC_FILE" ]; then
    log "ERROR: source file $SRC_FILE missing in $SCRIPT_DIR"
    zenity --error --title="Install package incomplete" \
      --text="❌ Source file missing:\n$SCRIPT_DIR/$SRC_FILE\n\nThe install package is incomplete.\nPlease re-clone the repo:\n  git clone $REPO_URL" \
      --width=500 2>/dev/null
    exit 1
  fi
  cp "$SCRIPT_DIR/$SRC_FILE" "$OLLAMAUI_DIR/" || {
    log "ERROR: failed to copy $SRC_FILE to $OLLAMAUI_DIR/"
    zenity --error --title="Copy failed" --text="❌ Could not copy $SRC_FILE\nCheck permissions on $OLLAMAUI_DIR" --width=400 2>/dev/null
    exit 1
  }
done
chmod +x "$OLLAMAUI_DIR/ollamaui-launcher.sh" "$OLLAMAUI_DIR/stopia.sh" "$OLLAMAUI_DIR/detect_browser.sh"
track "scripts"

# Symlink ollama-models in custom parent (if custom location)
if [ -n "$CUSTOM_PARENT" ]; then
  log "Setting up ollama-models symlink in $CUSTOM_PARENT..."
  SYMLINK_PATH="$CUSTOM_PARENT/ollama-models"
  REAL_TARGET="/usr/share/ollama/.ollama/models"
  
  if [ -L "$SYMLINK_PATH" ]; then
    CURRENT_TARGET=$(readlink "$SYMLINK_PATH")
    if [ "$CURRENT_TARGET" != "$REAL_TARGET" ]; then
      log "Symlink exists but points to wrong target — updating"
      rm "$SYMLINK_PATH"
      ln -s "$REAL_TARGET" "$SYMLINK_PATH"
      track "symlink"
    else
      log "Symlink already correct — nothing to do"
    fi
  elif [ -e "$SYMLINK_PATH" ]; then
    log "WARNING: $SYMLINK_PATH exists and is not a symlink — skipping"
  else
    ln -s "$REAL_TARGET" "$SYMLINK_PATH"
    track "symlink"
    log "✅ Symlink created: $SYMLINK_PATH → $REAL_TARGET"
  fi
fi

# Desktop shortcut
DESKTOP="$HOME/Desktop"
[ ! -d "$DESKTOP" ] && DESKTOP="$HOME/Bureau"
[ ! -d "$DESKTOP" ] && mkdir -p "$DESKTOP"
[ -f "$DESKTOP/OllamaUI.desktop" ] && cp "$DESKTOP/OllamaUI.desktop" "$DESKTOP/OllamaUI.desktop.bak"

# Copy icon to install dir so .desktop survives if user deletes the git repo
if [ -f "$SCRIPT_DIR/icon.png" ]; then
  cp "$SCRIPT_DIR/icon.png" "$OLLAMAUI_DIR/icon.png" 2>/dev/null
  ICON_PATH="$OLLAMAUI_DIR/icon.png"
else
  ICON_PATH="utilities-terminal"
fi

if [ "$WEBUI_MODE" = "external" ]; then
  cat > "$DESKTOP/OllamaUI.desktop" << DESK_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=OllamaUI
Comment=Open your existing Open WebUI
Exec=xdg-open $WEBUI_EXTERNAL_URL
Icon=$ICON_PATH
Terminal=false
Categories=Application;
DESK_EOF
else
  cat > "$DESKTOP/OllamaUI.desktop" << DESK_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=OllamaUI
Comment=Launch Ollama + Open WebUI (on-demand)
Exec=$OLLAMAUI_DIR/ollamaui-launcher.sh
Icon=$ICON_PATH
Terminal=false
Categories=Application;
DESK_EOF
fi
gio set "$DESKTOP/OllamaUI.desktop" metadata::trusted true 2>/dev/null
chmod +x "$DESKTOP/OllamaUI.desktop"
track "shortcut"
log "Desktop shortcut created at $DESKTOP/OllamaUI.desktop"
log "✅ Installation complete!"

# Final popup
FINAL_MSG="✅ Ollama + Open WebUI installed successfully!\n\n"
FINAL_MSG+="Desktop shortcut 'OllamaUI' created on your Bureau.\n"
FINAL_MSG+="Scripts installed at: $OLLAMAUI_DIR\n"
[ -n "$CUSTOM_PARENT" ] && FINAL_MSG+="Models accessible at: $CUSTOM_PARENT/ollama-models\n"
FINAL_MSG+="\n"
if [ "$WEBUI_MODE" = "external" ]; then
  FINAL_MSG+="The shortcut opens your existing WebUI at:\n  $WEBUI_EXTERNAL_URL\n\n"
fi
FINAL_MSG+="⚠️ You may need to log out and back in for group changes\n"
FINAL_MSG+="(render, video, ollama, docker) to take effect.\n\n"
FINAL_MSG+="Launch it now?"

zenity --question --title="Ollama Setup" --text="$FINAL_MSG" \
  --ok-label="✅ Launch now" --cancel-label="Later" \
  --width=500 2>/dev/null
if [ $? -eq 0 ]; then
  log "User chose: Launch now"
  if [ "$WEBUI_MODE" = "external" ]; then
    nohup xdg-open "$WEBUI_EXTERNAL_URL" >/dev/null 2>&1 &
  else
    nohup "$OLLAMAUI_DIR/ollamaui-launcher.sh" >/dev/null 2>&1 &
  fi
  disown
fi

log "Install script done"
exit 0
