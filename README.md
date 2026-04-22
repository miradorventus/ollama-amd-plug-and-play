# 🚀 Ollama + Open WebUI — AMD Plug & Play

> **One click. That's it.**

A dead-simple installer for **Ollama + Open WebUI** on Ubuntu with AMD GPU acceleration.
No terminal wizardry needed — just double-click and go.

---

## ✨ What you get

- 🖥️ **Desktop shortcut** to launch everything with one click
- 🤖 **Ollama** — run AI models locally on your AMD GPU
- 🌐 **Open WebUI** — a beautiful chat interface (like ChatGPT, but local!)
- 🔒 **100% offline** — your data never leaves your machine
- ⚡ **Auto stop** — closes everything when you close the browser
- 💾 **VRAM friendly** — models unload automatically after 5 minutes idle

---

## 🖥️ Requirements

| Component | Requirement |
|---|---|
| OS | Ubuntu 24.04 LTS |
| GPU | AMD with ROCm support (RX 6000 series and newer) |
| RAM | 16 GB minimum |
| Storage | 20 GB free minimum |
| Internet | Required for installation only |

> ⚠️ **RDNA4 users (RX 9070 / 9070 XT):** `HSA_OVERRIDE_GFX_VERSION=12.0.1` is already pre-configured in the scripts.

---

## 📦 Installation

**Copy this 👇 — Paste into a terminal — Press Enter — Enjoy! 🎉**

```bash
git clone https://github.com/miradorventus/ollama-amd-plug-and-play.git
cd ollama-amd-plug-and-play
chmod +x install_ollama.sh
./install_ollama.sh
```

The graphical installer will handle everything:

1. ✅ Ask for your password once (via a popup — no terminal needed after this)
2. ✅ Check and install Docker if needed
3. ✅ Detect your AMD GPU and ROCm drivers
4. ✅ Download Ollama and Open WebUI
5. ✅ Create a desktop shortcut **OllamaUI**
6. ✅ Launch everything automatically when done

---

## 🎮 Daily Usage

**Start:** Double-click **OllamaUI** on your desktop

**Stop:** Close the browser window — everything stops automatically

**Web interface:** `http://localhost:3000`

---

## 🗑️ Uninstall

**Copy this 👇 — Paste into a terminal — Done!**

```bash
cd ollama-amd-plug-and-play
./uninstall_ollama.sh
```

- Removes Docker containers and images
- Removes scripts and desktop shortcuts
- **Keeps your downloaded models** in `~/.ollama`

---

## 🤖 Download a Model

Open a terminal and run:

```bash
docker exec ollama ollama pull MODEL_NAME
```

**Examples:**

```bash
# Small and fast — good for low VRAM (4 GB+)
docker exec ollama ollama pull gemma3:4b

# Balanced — good all-rounder (8 GB+ VRAM)
docker exec ollama ollama pull gemma3:12b

# Best quality — needs more VRAM (16 GB+)
docker exec ollama ollama pull gemma4:26b

# Great for coding (5 GB+ VRAM)
docker exec ollama ollama pull qwen2.5:7b

# General purpose, fast (4 GB+ VRAM)
docker exec ollama ollama pull mistral:7b
```

**List your installed models:**
```bash
docker exec ollama ollama list
```

**Delete a model to free space:**
```bash
docker exec ollama ollama rm gemma3:4b
```

### VRAM Guide

| Your VRAM | Recommended models |
|---|---|
| 4 GB | `gemma3:4b`, `phi3:mini` |
| 8 GB | `gemma3:12b`, `llama3:8b` |
| 12 GB | `gemma3:12b`, `mistral:12b` |
| 16 GB | `gemma4:26b`, `llama3:70b-q4` |
| 24 GB+ | Any model |

> 💡 If a model is too large for your VRAM, Ollama automatically uses system RAM as overflow — slower, but it still works!

---

## 🔧 Useful Commands

**Check GPU is being used (run during a generation):**
```bash
watch -n 1 docker exec ollama ollama ps
# Look for "GPU" in the PROCESSOR column ✅
```

**Restart if something goes wrong:**
```bash
docker restart ollama
docker restart open-webui
```

**View error logs:**
```bash
docker logs ollama
docker logs open-webui
```

See **MEMO.txt** for the full command reference.

---

## 💬 Contributing

All feedback is welcome — bugs, suggestions, improvements, anything!

→ Open an **Issue**
→ Submit a **Pull Request**
→ Share your experience

This project is made by a fellow AMD Linux user, for AMD Linux users. 🤝

---

## 📄 License

MIT — Free to use, modify and share.
