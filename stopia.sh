#!/bin/bash
echo "--- Arrêt des services IA ---"

echo "Arrêt d'Open WebUI..."
docker stop open-webui > /dev/null 2>&1
docker update --restart=no open-webui > /dev/null 2>&1

echo "Arrêt d'Ollama..."
docker stop ollama > /dev/null 2>&1

echo "--- Ressources libérées ---"
zenity --notification \
  --text="✅ OllamaUI arrêté — GPU libéré" \
  --timeout=2 2>/dev/null &
