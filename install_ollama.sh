#!/bin/bash
# ============================================================
#  install_ollama.sh
#  Installateur Ollama + Open WebUI (AMD ROCm)
#  Bilingue FR/EN — Interface graphique zenity
#  Testé sur Ubuntu 24.04 / RX 9070 XT / ROCm 7.2
# ============================================================

LOG_FILE="$HOME/install_ollama.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Zenity disponible ? ---
if ! command -v zenity &>/dev/null; then
  sudo apt install zenity -y
fi

# --- Authentification sudo via popup ---
if ! sudo -n true 2>/dev/null; then
  PASSWORD=$(zenity --password \
    --title="Authentification requise" \
    --text="Entrez votre mot de passe administrateur :" \
    --width=400 2>/dev/null)
  [ $? -ne 0 ] && exit 0
  echo "$PASSWORD" | sudo -S -v 2>/dev/null || {
    zenity --error \
      --title="Erreur d'authentification" \
      --text="❌ Mot de passe incorrect.\nInstallation annulée." \
      --width=350 2>/dev/null
    exit 1
  }
fi

# --- Langue ---
LANG_SYS=$(echo $LANG | cut -d_ -f1)
if [ "$LANG_SYS" = "fr" ]; then
  MSG_WELCOME="Bienvenue dans l'installateur Ollama + Open WebUI\n\nCet outil va installer :\n• Ollama (moteur IA local) avec accélération GPU AMD\n• Open WebUI (interface web)\n\nConfiguration requise :\n• Ubuntu 24.04\n• GPU AMD avec ROCm\n• Connexion internet\n\nLog : $LOG_FILE"
  MSG_GPU_ERR="❌ Aucun GPU AMD détecté.\n\n/dev/kfd est introuvable.\nVérifiez que vos pilotes AMD ROCm sont installés.\n\nVoulez-vous installer ROCm maintenant ?"
  MSG_DOCKER_MISSING="Docker n'est pas installé.\nVoulez-vous l'installer maintenant ?"
  MSG_SHORTCUT_EXISTS="Un raccourci OllamaUI existe déjà sur le bureau.\nVoulez-vous le remplacer ?\n\n(L'ancien sera sauvegardé en .bak)"
  MSG_SUCCESS="✅ Ollama + Open WebUI installés avec succès !\n\nUn raccourci 'OllamaUI' a été créé sur votre bureau.\n\nVoulez-vous lancer OllamaUI maintenant ?"
  MSG_FAIL="❌ L'installation a échoué.\n\nConsultez le log ici :\n$LOG_FILE"
  MSG_REBOOT="⚠️ Un redémarrage est nécessaire pour finaliser l'installation des pilotes.\nRedémarrer maintenant ?"
  MSG_VIEW_LOG="Voir le log"
  MSG_SAVE_LOG="Sauvegarder le log"
  MSG_CANCEL="Installation annulée."
else
  MSG_WELCOME="Welcome to the Ollama + Open WebUI installer\n\nThis tool will install:\n• Ollama (local AI engine) with AMD GPU acceleration\n• Open WebUI (web interface)\n\nRequirements:\n• Ubuntu 24.04\n• AMD GPU with ROCm\n• Internet connection\n\nLog: $LOG_FILE"
  MSG_GPU_ERR="❌ No AMD GPU detected.\n\n/dev/kfd not found.\nPlease check that AMD ROCm drivers are installed.\n\nDo you want to install ROCm now?"
  MSG_DOCKER_MISSING="Docker is not installed.\nDo you want to install it now?"
  MSG_SHORTCUT_EXISTS="An OllamaUI shortcut already exists on the desktop.\nDo you want to replace it?\n\n(The old one will be saved as .bak)"
  MSG_SUCCESS="✅ Ollama + Open WebUI installed successfully!\n\nAn 'OllamaUI' shortcut has been created on your desktop.\n\nDo you want to launch OllamaUI now?"
  MSG_FAIL="❌ Installation failed.\n\nSee the log here:\n$LOG_FILE"
  MSG_REBOOT="⚠️ A reboot is required to finalize driver installation.\nReboot now?"
  MSG_VIEW_LOG="View log"
  MSG_SAVE_LOG="Save log"
  MSG_CANCEL="Installation cancelled."
fi

# --- Fonctions ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
  log "ERREUR: $1"
  zenity --error \
    --title="Ollama Setup — Erreur" \
    --text="$MSG_FAIL" \
    --extra-button="$MSG_VIEW_LOG" \
    --extra-button="$MSG_SAVE_LOG" \
    --width=450 2>/dev/null
  case $? in
    1) zenity --text-info --title="Log" --filename="$LOG_FILE" --width=800 --height=500 2>/dev/null ;;
    2)
      DEST="$HOME/Desktop/install_ollama.log"
      [ ! -d "$HOME/Desktop" ] && DEST="$HOME/Bureau/install_ollama.log"
      cp "$LOG_FILE" "$DEST"
      zenity --info --title="Log sauvegardé" --text="Log sauvegardé dans :\n$DEST" --width=350 2>/dev/null
      ;;
  esac
  exit 1
}

# --- Init log ---
echo "============================================" > "$LOG_FILE"
echo " Ollama + Open WebUI — Log d'installation"  >> "$LOG_FILE"
echo " $(date)"                                    >> "$LOG_FILE"
echo " Système : $(uname -a)"                      >> "$LOG_FILE"
echo " Ubuntu  : $(lsb_release -d 2>/dev/null | cut -f2)" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

# --- Bienvenue ---
zenity --info \
  --title="Ollama + Open WebUI Setup" \
  --text="$MSG_WELCOME" \
  --width=500 2>/dev/null
[ $? -ne 0 ] && echo "$MSG_CANCEL" && exit 0

# --- Vérification Docker ---
if ! command -v docker &>/dev/null; then
  zenity --question \
    --title="Ollama Setup" \
    --text="$MSG_DOCKER_MISSING" \
    --width=400 2>/dev/null
  if [ $? -eq 0 ]; then
    (
      echo "10:Mise à jour des paquets..."
      sudo apt update >> "$LOG_FILE" 2>&1
      echo "50:Installation de Docker..."
      sudo apt install docker.io -y >> "$LOG_FILE" 2>&1
      echo "80:Configuration des groupes..."
      sudo usermod -aG docker $USER >> "$LOG_FILE" 2>&1
      echo "100:Docker installé !"
    ) | zenity --progress \
      --title="Installation Docker" \
      --text="Installation de Docker..." \
      --percentage=0 --auto-close --width=450 2>/dev/null
    log "OK: Docker installé"
  else
    error_exit "Docker requis mais non installé."
  fi
fi

# --- Vérification ROCm / GPU ---
if [ ! -e /dev/kfd ]; then
  zenity --question \
    --title="Ollama Setup" \
    --text="$MSG_GPU_ERR" \
    --width=450 2>/dev/null
  if [ $? -eq 0 ]; then
    (
      echo "5:Téléchargement du paquet AMD..."
      wget -q "https://repo.radeon.com/amdgpu-install/6.3.3/ubuntu/noble/amdgpu-install_6.3.60303-1_all.deb" \
        -O /tmp/amdgpu-install.deb >> "$LOG_FILE" 2>&1
      echo "30:Installation du dépôt AMD..."
      sudo apt install /tmp/amdgpu-install.deb -y >> "$LOG_FILE" 2>&1
      echo "50:Installation ROCm..."
      sudo amdgpu-install --usecase=rocm,hip --no-dkms -y >> "$LOG_FILE" 2>&1
      echo "90:Configuration des groupes..."
      sudo usermod -aG render,video $USER >> "$LOG_FILE" 2>&1
      echo "100:ROCm installé !"
    ) | zenity --progress \
      --title="Installation ROCm" \
      --text="Installation des pilotes AMD ROCm..." \
      --percentage=0 --auto-close --width=450 2>/dev/null
    log "OK: ROCm installé"
    zenity --question --title="Ollama Setup" --text="$MSG_REBOOT" --width=400 2>/dev/null
    [ $? -eq 0 ] && sudo reboot
    exit 0
  else
    error_exit "GPU AMD requis mais non détecté."
  fi
fi

# --- Installation Ollama + Open WebUI ---
(
  echo "5:Téléchargement de l'image Ollama ROCm..."
  log "Téléchargement ollama/ollama:rocm"
  docker pull ollama/ollama:rocm >> "$LOG_FILE" 2>&1 || { log "ERREUR: docker pull ollama"; exit 1; }

  echo "35:Téléchargement d'Open WebUI..."
  log "Téléchargement open-webui"
  docker pull ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1 || { log "ERREUR: docker pull open-webui"; exit 1; }

  echo "60:Création du container Ollama..."
  docker stop ollama 2>/dev/null; docker rm ollama 2>/dev/null
  docker run -d --name ollama \
    -p 11434:11434 \
    -v "$HOME/.ollama":/root/.ollama \
    --device /dev/kfd \
    --device /dev/dri \
    -e OLLAMA_KEEP_ALIVE=5m \
    -e HSA_OVERRIDE_GFX_VERSION=12.0.1 \
    -e OLLAMA_LLM_LIBRARY=rocm \
    ollama/ollama:rocm >> "$LOG_FILE" 2>&1 || { log "ERREUR: création container ollama"; exit 1; }

  echo "70:Création du container Open WebUI..."
  docker stop open-webui 2>/dev/null; docker rm open-webui 2>/dev/null
  docker run -d --name open-webui \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    --restart always \
    ghcr.io/open-webui/open-webui:main >> "$LOG_FILE" 2>&1 || { log "ERREUR: création container open-webui"; exit 1; }

  echo "78:Copie des scripts..."
  cp "$SCRIPT_DIR/ollamaui.sh" "$HOME/"
  cp "$SCRIPT_DIR/stopia.sh" "$HOME/"
  cp "$SCRIPT_DIR/../detect_browser.sh" "$HOME/"
  chmod +x "$HOME/ollamaui.sh" "$HOME/stopia.sh" "$HOME/detect_browser.sh"

  echo "85:Gestion du raccourci bureau..."
  DESKTOP="$HOME/Desktop"
  [ ! -d "$DESKTOP" ] && DESKTOP="$HOME/Bureau"

  CREATE_SHORTCUT=true
  if [ -f "$DESKTOP/OllamaUI.desktop" ]; then
    cp "$DESKTOP/OllamaUI.desktop" "$DESKTOP/OllamaUI.desktop.bak"
    zenity --question --title="Ollama Setup" --text="$MSG_SHORTCUT_EXISTS" --width=400 2>/dev/null
    [ $? -ne 0 ] && CREATE_SHORTCUT=false
  fi

  if [ "$CREATE_SHORTCUT" = true ]; then
    cat > "$DESKTOP/OllamaUI.desktop" << DESK
[Desktop Entry]
Version=1.0
Type=Application
Name=OllamaUI
Comment=Lancer Ollama et Open WebUI
Exec=bash -c "$HOME/ollamaui.sh > $HOME/ollamaui.log 2>&1"
Icon=utilities-terminal
Terminal=false
Categories=Application;
DESK
    gio set "$DESKTOP/OllamaUI.desktop" metadata::trusted true 2>/dev/null
    chmod +x "$DESKTOP/OllamaUI.desktop"
  fi

  echo "90:Configuration réseau permanente..."
  sudo apt install iptables-persistent -y >> "$LOG_FILE" 2>&1
  sudo iptables -P FORWARD ACCEPT
  sudo netfilter-persistent save >> "$LOG_FILE" 2>&1
  sudo systemctl enable netfilter-persistent >> "$LOG_FILE" 2>&1

  sudo tee /etc/systemd/system/fix-network.service > /dev/null << 'SVC'
[Unit]
Description=Fix réseau filaire au démarrage
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli con down "Connexion filaire 1"
ExecStartPost=/bin/sleep 2
ExecStartPost=/usr/bin/nmcli con up "Connexion filaire 1"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
  sudo systemctl enable fix-network.service >> "$LOG_FILE" 2>&1

  log "OK: Installation Ollama + Open WebUI terminée"
  echo "100:Installation terminée !"

) | zenity --progress \
  --title="Installation Ollama + Open WebUI" \
  --text="Installation en cours, veuillez patienter..." \
  --percentage=0 \
  --auto-close \
  --width=500 2>/dev/null || error_exit "Une erreur est survenue pendant l'installation."

# --- Succès ---
zenity --info \
  --title="Ollama Setup" \
  --text="$MSG_SUCCESS" \
  --extra-button="$MSG_VIEW_LOG" \
  --extra-button="$MSG_SAVE_LOG" \
  --width=450 2>/dev/null

case $? in
  0) bash "$HOME/ollamaui.sh" & ;;
  1) zenity --text-info --title="Log" --filename="$LOG_FILE" --width=800 --height=500 2>/dev/null ;;
  2)
    DEST="$HOME/Desktop/install_ollama.log"
    [ ! -d "$HOME/Desktop" ] && DEST="$HOME/Bureau/install_ollama.log"
    cp "$LOG_FILE" "$DEST"
    zenity --info --title="Log sauvegardé" --text="Log sauvegardé dans :\n$DEST" --width=350 2>/dev/null
    ;;
esac

exit 0
