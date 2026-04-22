#!/bin/bash

LANG_SYS=$(echo $LANG | cut -d_ -f1)
if [ "$LANG_SYS" = "fr" ]; then
  MSG="⚠️ Voulez-vous désinstaller Ollama + Open WebUI ?\n\nVos modèles seront conservés dans ~/.ollama"
  MSG_OK="✅ Désinstallation terminée !\n\nVos modèles sont conservés dans ~/.ollama"
else
  MSG="⚠️ Do you want to uninstall Ollama + Open WebUI?\n\nYour models will be kept in ~/.ollama"
  MSG_OK="✅ Uninstallation complete!\n\nYour models are kept in ~/.ollama"
fi

zenity --question --title="AMD AI Setup — Désinstallation" --text="$MSG" --width=400 2>/dev/null
[ $? -ne 0 ] && exit 0

(
  echo "20:Arrêt des containers..."
  docker ps -a --format '{{.Names}}' | grep -E "ollama|open-webui" | xargs -r docker rm -f 2>/dev/null

  echo "50:Suppression des images Docker..."
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "ollama|open-webui" | xargs -r docker rmi -f 2>/dev/null

  echo "70:Suppression des scripts..."
  rm -f ~/ollamaui.sh ~/stopia.sh ~/detect_browser.sh

  echo "85:Suppression des raccourcis bureau..."
  rm -f ~/Bureau/OllamaUI.desktop ~/Desktop/OllamaUI.desktop

  echo "100:Terminé !"
) | zenity --progress \
  --title="Désinstallation" \
  --text="Désinstallation en cours..." \
  --percentage=0 --auto-close --width=450 2>/dev/null

zenity --info --title="AMD AI Setup" --text="$MSG_OK" --width=400 2>/dev/null
