#!/bin/bash
# ============================================================
#  stopia.sh — Stop Ollama (Open WebUI + TTS suivent en cascade)
# ============================================================

echo "--- Stopping AI services ---"
echo "Stopping Ollama service..."
sudo systemctl stop ollama > /dev/null 2>&1
echo "--- GPU freed ---"

# Notification bloquante (le script attend qu'elle se ferme)
zenity --info \
  --title="OllamaUI" \
  --text="✅ OllamaUI stopped — GPU freed" \
  --width=350 \
  --timeout=3 2>/dev/null
