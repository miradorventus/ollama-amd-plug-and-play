#!/bin/bash
# ============================================================
#  stopia.sh — Stop Ollama + Open WebUI (on-demand policy)
# ============================================================

echo "--- Stopping AI services ---"

echo "Stopping Open WebUI..."
docker stop open-webui > /dev/null 2>&1

echo "Stopping Ollama service..."
sudo systemctl stop ollama > /dev/null 2>&1

echo "--- GPU freed ---"

zenity --notification \
  --text="✅ OllamaUI stopped — GPU freed" \
  --timeout=2 2>/dev/null &
