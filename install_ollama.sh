#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Ollama (native) + Open WebUI (Docker) — AMD ROCm
#  Version: 1.5.0
# ============================================================
#  Sources used (all official):
#    • Ollama:    https://ollama.com/install.sh
#    • WebUI:     ghcr.io/open-webui/open-webui (GitHub)
#    • ROCm:      https://repo.radeon.com (AMD)
#    • Docker:    Ubuntu/Mint apt repos
# ============================================================

VERSION="1.5.0"
LOG_FILE="$HOME/install_ollama.log"
STATUS_FILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_FILE="$HOME/.config/autostart/ollama-install-resume.desktop"

# Track what's been done — used by rollback() if user aborts
TRACK_FILE=$(mktemp --suffix=-ollama-track)
track() { echo "$1" >> "$TRACK_FILE"; }
was_done() { grep -q "^$1$" "$TRACK_FILE" 2>/dev/null; }

# ─── Runtime requirements ────────────────────────────────────
command -v zenity &>/dev/null || sudo apt install -y zenity
rm -f "$AUTOSTART_FILE"  # post-reboot cleanup

# ─── Init log ────────────────────────────────────────────────
cat > "$LOG_FILE" << LOG_EOF
============================================
 Ollama + Open WebUI — Installation log
 $(date)
 Version: $VERSION
============================================
LOG_EOF
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# ─── Auth: askpass (zenity, works with or without TTY) ──────
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

# ─── Cleanup & rollback functions ────────────────────────────
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
    rm -f "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"
    log "  Removed launch scripts"
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

cleanup_full() {
  cleanup_auth
}

trap cleanup_full EXIT

# Confirmed stop with rollback summary popup
confirm_stop_and_exit() {
  local items=""
  was_done "ollama_binary"   && items+="  • Ollama binary + service\n"
  was_done "ollama_systemd"  && items+="  • Ollama systemd config + sudoers\n"
  was_done "webui"           && items+="  • Open WebUI container\n"
  was_done "ufw"             && items+="  • UFW firewall rule\n"
  was_done "scripts"         && items+="  • Launch scripts in \$HOME\n"
  was_done "shortcut"        && items+="  • Desktop shortcut\n"
  
  local kept=""
  was_done "rocm" && kept+="  • ROCm 6.3 (10 GB) — to remove:\n      sudo apt remove --purge 'rocm-*' 'hip-*'\n      sudo apt autoremove\n"
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
  
  # zenity --question : OK=0, Cancel=1
  # We INVERT the labels so OK=stop, Cancel=keep installing
  # Default focus is on Cancel (✅ Cancel — keep installing) for safety
  if [ $? -eq 0 ]; then
    rollback
    log "User confirmed stop. Rollback done."
    exit 0
  fi
  # Otherwise return — the caller decides what to do
  return 1
}

# ─── PRE-CHECK ───────────────────────────────────────────────
log "=== Pre-check ==="

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

# Desktop shortcut already present?
PRE_CHECK_SHORTCUT=0
for d in "$HOME/Desktop" "$HOME/Bureau"; do
  [ -f "$d/OllamaUI.desktop" ] && PRE_CHECK_SHORTCUT=1
done

log "Pre-check: OS=$OS_NAME ROCm=$PRE_CHECK_ROCM Docker=$PRE_CHECK_DOCKER Curl=$PRE_CHECK_CURL Ollama=$PRE_CHECK_OLLAMA OllamaEnabled=$PRE_CHECK_OLLAMA_ENABLED WebUI=$PRE_CHECK_WEBUI UFWActive=$PRE_CHECK_UFW_ACTIVE Shortcut=$PRE_CHECK_SHORTCUT"

# ─── Build dynamic welcome message ───────────────────────────
WELCOME="Welcome to the Ollama + Open WebUI installer\n\n"
WELCOME+="Detected on your system:\n"
[ "$PRE_CHECK_OS_OK" = "1" ] && WELCOME+="  ✅ $OS_NAME\n" || WELCOME+="  ⚠️ $OS_NAME (untested)\n"
[ "$PRE_CHECK_CURL" = "1" ]   && WELCOME+="  ✅ curl\n"          || WELCOME+="  ⬜ curl — will install\n"
[ "$PRE_CHECK_DOCKER" = "1" ] && WELCOME+="  ✅ Docker\n"        || WELCOME+="  ⬜ Docker — will install (~50 MB)\n"

TOTAL_DL=0
REBOOT_NEEDED=0
if [ "$PRE_CHECK_ROCM" = "1" ]; then
  WELCOME+="  ✅ ROCm 6.3\n"
else
  WELCOME+="  ⬜ ROCm 6.3 — will install from repo.radeon.com (~10 GB)\n"
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
WELCOME+="• Nothing runs at boot — saves power!\n\n"
WELCOME+="Log: $LOG_FILE"

# ─── Welcome popup ───────────────────────────────────────────
zenity --question --title="Ollama Setup" --text="$WELCOME" \
  --ok-label="✅ Continue" --cancel-label="❌ Cancel" \
  --width=550 2>/dev/null
[ $? -ne 0 ] && { log "Cancelled at welcome"; exit 0; }

# ─── Auth: prime sudo cache ──────────────────────────────────
log "Authenticating..."
if ! sudo -A -v 2>/dev/null; then
  zenity --error --title="Authentication cancelled" \
    --text="❌ Installation cancelled (no password)." --width=400 2>/dev/null
  exit 1
fi
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPER_PID=$!

# ─── Helper: show progress while a command runs ──────────────
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
#  STEP 1/3 — DEPENDENCIES (ROCm + Docker + curl)
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
      rocm)   STEP1_MSG+="  • ROCm 6.3 (repo.radeon.com)\n" ;;
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
    # If user changed their mind, we just skip this step (won't happen on first run)
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
            log "Installing ROCm 6.3..."
            log "Step 1: download GPG key + add official AMD repos..."
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
            echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/6.3.3/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/amdgpu.list > /dev/null
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.3.3 noble main" | sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null
            log "Step 2: download official amdgpu-install .deb..."
            wget -q "https://repo.radeon.com/amdgpu-install/6.3.3/ubuntu/noble/amdgpu-install_6.3.60303-1_all.deb" -O /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
            log "Step 3: install amdgpu-install package..."
            sudo apt install --reinstall -y /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
            log "Step 4: refresh apt cache (repos now active)..."
            sudo apt update >> "$LOG_FILE" 2>&1
            log "Step 5: install ROCm + HIP packages..."
            sudo amdgpu-install --usecase=rocm,hip --no-dkms -y >> "$LOG_FILE" 2>&1
            log "Step 6: add user to render,video groups..."
            sudo usermod -aG render,video $USER >> "$LOG_FILE" 2>&1
            # Verify ROCm actually installed
            if dpkg -l | grep -q "^ii  rocm-hip-runtime"; then
              log "✅ ROCm installed successfully"
              track "rocm"
              echo "REBOOT" > "$STATUS_FILE"
            else
              log "❌ ERROR: ROCm install failed (rocm-hip-runtime not present after install)"
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
        --text="❌ Failed to install ROCm.\n\nCheck the log: $LOG_FILE\n\nMake sure your system has internet access\nand that AMD repos are reachable." --width=450 2>/dev/null
      exit 1
    fi
    log "Step 1/3 done"
  fi
fi

# ─── REBOOT FLOW (if ROCm was just installed) ───────────────
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
    log "User chose: Import existing Ollama"
    while true; do
      OLLAMA_MODELS_PATH=$(zenity --file-selection --directory \
        --title="Select your existing Ollama folder" \
        --filename="$HOME/.ollama/" 2>/dev/null)
      if [ -z "$OLLAMA_MODELS_PATH" ]; then
        log "User cancelled folder picker — going back to install fresh path"
        OLLAMA_MODELS_PATH=""
        STEP2_CODE=0
        break
      fi
      # Validate: a real Ollama folder contains models/ or blobs/
      if [ -d "$OLLAMA_MODELS_PATH/models" ] || [ -d "$OLLAMA_MODELS_PATH/blobs" ] || \
         [ -d "$OLLAMA_MODELS_PATH/manifests" ]; then
        log "Valid Ollama folder: $OLLAMA_MODELS_PATH"
        STEP2_CODE=0
        break
      else
        zenity --question --title="Not a valid Ollama folder" \
          --text="The folder you selected does not look like an Ollama data folder.\n\nA valid Ollama folder contains:\n  • models/  or  blobs/  or  manifests/\n\n[Try another folder] [Install fresh instead]" \
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
  
  # Install or configure Ollama
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
    
    # Merge: read existing values, preserve user customs, force OLLAMA_HOST=0.0.0.0
    EXISTING_OVERRIDE=""
    [ -f /etc/systemd/system/ollama.service.d/override.conf ] && \
      EXISTING_OVERRIDE=$(sudo cat /etc/systemd/system/ollama.service.d/override.conf)
    
    # Build new override
    NEW_OVERRIDE="[Service]"
    
    # Default values we want
    declare -A REQUIRED=( \
      ["HSA_OVERRIDE_GFX_VERSION"]="12.0.1" \
      ["OLLAMA_LLM_LIBRARY"]="rocm" \
      ["OLLAMA_KEEP_ALIVE"]="5m" \
    )
    # Critical: OLLAMA_HOST MUST be 0.0.0.0 for WebUI
    REQUIRED["OLLAMA_HOST"]="0.0.0.0"
    
    # Add OLLAMA_MODELS if importing
    [ -n "$OLLAMA_MODELS_PATH" ] && REQUIRED["OLLAMA_MODELS"]="$OLLAMA_MODELS_PATH"
    
    for key in "${!REQUIRED[@]}"; do
      USER_VAL=$(echo "$EXISTING_OVERRIDE" | grep -oP "Environment=\"$key=\K[^\"]+" | head -1)
      if [ "$key" = "OLLAMA_HOST" ]; then
        # Force our value
        NEW_OVERRIDE+="\nEnvironment=\"$key=${REQUIRED[$key]}\""
      elif [ -n "$USER_VAL" ]; then
        # Preserve user's existing
        NEW_OVERRIDE+="\nEnvironment=\"$key=$USER_VAL\""
      else
        # Use our default
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
    
    # Q2: respect user's existing enable preference
    if [ "$PRE_CHECK_OLLAMA_ENABLED" = "1" ]; then
      log "Ollama was already enabled — keeping user's preference"
    else
      log "Disabling Ollama auto-start (on-demand policy)..."
      sudo systemctl disable ollama >> "$LOG_FILE" 2>&1
      sudo systemctl stop ollama >> "$LOG_FILE" 2>&1
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
WEBUI_MODE="install"  # default: fresh install
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
    log "User chose: external WebUI"
    WEBUI_EXTERNAL_URL=$(zenity --entry --title="Your Open WebUI URL" \
      --text="You already have Open WebUI running. Great!\n\nPaste its URL below.\n\nExamples:\n  http://127.0.0.1:3000   (default port)\n  http://192.168.1.50:3000   (another machine)\n  http://localhost:8080   (custom port)\n\nURL:" \
      --width=520 2>/dev/null)
    if [ -z "$WEBUI_EXTERNAL_URL" ]; then
      log "User cancelled URL prompt — going to fresh install"
      WEBUI_MODE="install"
    else
      WEBUI_MODE="external"
      log "External WebUI URL: $WEBUI_EXTERNAL_URL"
    fi
  elif [ $STEP3_CODE -ne 0 ]; then
    confirm_stop_and_exit
  fi
fi

# Install WebUI if needed
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
      -p 3000:8080 \
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

# UFW rule — re-check now (sudo cache is primed at this point)
# Multi-language: active / actif
if command -v ufw &>/dev/null && \
   sudo ufw status 2>/dev/null | head -1 | grep -qiE "active|actif"; then
  log "UFW is active — adding rule for Docker subnet → port 11434"
  sudo ufw allow from 172.17.0.0/16 to any port 11434 proto tcp comment 'Ollama for Docker containers' 2>/dev/null
  sudo ufw reload 2>/dev/null
  track "ufw"
else
  log "UFW not active — no firewall rule needed"
fi

# Install scripts + desktop shortcut
log "Installing launch scripts..."
cp "$SCRIPT_DIR/ollamaui.sh" "$HOME/" 2>/dev/null
cp "$SCRIPT_DIR/stopia.sh" "$HOME/" 2>/dev/null
cp "$SCRIPT_DIR/detect_browser.sh" "$HOME/" 2>/dev/null
chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh" 2>/dev/null
track "scripts"

DESKTOP="$HOME/Desktop"
[ ! -d "$DESKTOP" ] && DESKTOP="$HOME/Bureau"
[ ! -d "$DESKTOP" ] && mkdir -p "$DESKTOP"
[ -f "$DESKTOP/OllamaUI.desktop" ] && cp "$DESKTOP/OllamaUI.desktop" "$DESKTOP/OllamaUI.desktop.bak"
ICON_PATH="$SCRIPT_DIR/icon.png"
[ ! -f "$ICON_PATH" ] && ICON_PATH="utilities-terminal"

if [ "$WEBUI_MODE" = "external" ]; then
  # Shortcut points directly to user's URL
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
Exec=$HOME/ollamaui.sh
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

# ============================================================
#  FINAL POPUP — Launch now?
# ============================================================
FINAL_MSG="✅ Ollama + Open WebUI installed successfully!\n\n"
FINAL_MSG+="Desktop shortcut 'OllamaUI' created on your Bureau.\n\n"
if [ "$WEBUI_MODE" = "external" ]; then
  FINAL_MSG+="The shortcut opens your existing WebUI at:\n  $WEBUI_EXTERNAL_URL\n\n"
fi
FINAL_MSG+="Launch it now?"

zenity --question --title="Ollama Setup" --text="$FINAL_MSG" \
  --ok-label="✅ Launch now" --cancel-label="Later" \
  --width=450 2>/dev/null
if [ $? -eq 0 ]; then
  log "User chose: Launch now"
  if [ "$WEBUI_MODE" = "external" ]; then
    nohup xdg-open "$WEBUI_EXTERNAL_URL" >/dev/null 2>&1 &
  else
    nohup "$HOME/ollamaui.sh" >/dev/null 2>&1 &
  fi
  disown
fi

log "Install script done"
exit 0
