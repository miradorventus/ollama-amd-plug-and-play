#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=12.0.1
export OLLAMA_LLM_LIBRARY=rocm
export LD_LIBRARY_PATH=/usr/local/lib/ollama/rocm:$LD_LIBRARY_PATH

error_popup() {
  zenity --error --title="OllamaUI — Erreur" --text="$1" --extra-button="Voir les logs" --width=400 2>/dev/null
  if [ $? -eq 1 ]; then
    zenity --text-info --title="Logs OllamaUI" --filename=/home/ia/ollamaui.log --width=700 --height=400 2>/dev/null
  fi
}

if docker ps --format '{{.Names}}' | grep -q "open-webui"; then
  xdg-open http://localhost:3000
  exit 0
fi

nmcli con up "Connexion filaire 1" > /dev/null 2>&1
sudo iptables -P FORWARD ACCEPT

echo "Démarrage d'Ollama (ROCm)..."
docker start ollama > /dev/null 2>&1 || \
  docker run -d --name ollama \
    -p 11434:11434 \
    -v /home/ia/.ollama:/root/.ollama \
    --device /dev/kfd \
    --device /dev/dri \
    -e OLLAMA_KEEP_ALIVE=5m \
    -e HSA_OVERRIDE_GFX_VERSION=12.0.1 \
    -e OLLAMA_LLM_LIBRARY=rocm \
    ollama/ollama:rocm

echo "Démarrage d'Open WebUI..."
docker start open-webui > /dev/null 2>&1 || \
  docker run -d \
    --name open-webui \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    --restart always \
    ghcr.io/open-webui/open-webui:main

sleep 5

if ! curl -s http://localhost:11434 > /dev/null 2>&1; then
  error_popup "❌ Ollama ne répond pas.\nVérifiez que le GPU AMD est détecté et que Docker fonctionne."
  exit 1
fi

if ! curl -s http://localhost:3000 > /dev/null 2>&1; then
  error_popup "❌ Open WebUI ne répond pas.\nVérifiez les logs pour plus de détails."
  exit 1
fi

BROWSER=$(/home/ia/detect_browser.sh | cut -d'|' -f1)
echo "Navigateur détecté : $BROWSER"

case "$BROWSER" in
  firefox)
    PROFILE_DIR="/home/ia/snap/firefox/common/.mozilla/firefox/s74nrxf4.ollamaui"
    mkdir -p "$PROFILE_DIR"
    firefox --no-remote --profile "$PROFILE_DIR" http://localhost:3000 2>/dev/null
    ;;
  microsoft-edge)
    microsoft-edge --profile-directory="OllamaUI" http://localhost:3000 2>/dev/null
    ;;
  google-chrome)
    google-chrome --profile-directory="OllamaUI" http://localhost:3000 2>/dev/null
    ;;
  *)
    xdg-open http://localhost:3000
    sleep infinity
    ;;
esac

echo "Navigateur fermé, arrêt des services..."
/home/ia/stopia.sh
