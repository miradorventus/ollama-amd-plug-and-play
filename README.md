<p align="center"><img src="icon.png" width="200"/></p>

# 🚀 Ollama + Open WebUI — AMD Plug & Play

## 🎉 What's new — v1.1.2

- 🔐 **Smart authentication** — password prompt appears BEFORE anything else via native pkexec dialog
- 🔑 **NOPASSWD for stop only** — no password needed when closing the app
- 🔄 **Update check BEFORE launch** — if a new version is available, you're prompted immediately with auto-restart
- 👥 **Already-running detection** — clicking OllamaUI while running shows "New tab" or "Reset services" with confirmation
- ⚡ **Startup loading window** — visual feedback during initialization
- 🌐 **Fixed DNS timeout** — now uses `127.0.0.1` instead of `localhost`


> **No terminal gymnastics. No dependency hell. Just vibes and working AI.**

Tired of spending your Saturday configuring PyTorch, Docker, ROCm, systemd and 47 browser tabs of Stack Overflow?
Yeah, same. That's why this exists.

**One command. One click. Working AI on your AMD GPU.**

---

## ✨ What you get

- 🖥️ **Desktop shortcut** — double-click, that's the whole workflow
- 🤖 **Ollama** — native install (not Docker!) with full AMD ROCm acceleration
- 🌐 **Open WebUI** — the ChatGPT-looking interface, but running on your machine
- 🔒 **100% offline** — your data doesn't leave your GPU
- ⚡ **Smart on-demand** — services start when you click, stop when you close
- 💾 **VRAM friendly** — models auto-unload after 5 minutes of silence
- 🔋 **Power efficient** — no services running at boot, no wasted wattage

---

## 🖥️ Requirements

| Component | Requirement |
|---|---|
| OS | Ubuntu 24.04 LTS |
| GPU | AMD with ROCm support (RX 6000 series and newer) |
| RAM | 16 GB minimum |
| Storage | 20 GB free minimum |
| Internet | For the initial setup only |

> ⚠️ **RDNA4 gang (RX 9070 / 9070 XT):** `HSA_OVERRIDE_GFX_VERSION=12.0.1` is already wired up. You're welcome.

---

## 📦 Installation

**Copy this 👇 — Paste into terminal — Grab a coffee ☕**

```bash
git clone https://github.com/miradorventus/ollama-amd-plug-and-play.git
cd ollama-amd-plug-and-play
chmod +x install_ollama.sh
./install_ollama.sh
```

The installer handles everything — GUI all the way:

1. ✅ Asks for your password once (in a popup, not a terminal prompt)
2. ✅ Detects what's missing (Docker, curl, ROCm) and offers to install it
3. ✅ Pulls Ollama from the official source (native, not Docker)
4. ✅ Pulls Open WebUI (Docker, because why reinvent the wheel)
5. ✅ Configures Ollama for your AMD GPU automatically
6. ✅ Disables auto-start at boot (power efficiency ftw)
7. ✅ Creates an **OllamaUI** desktop shortcut

Live log window shows what's happening. No more `tail -f` in a hidden terminal.

---

## 🎮 Daily Usage

**Start:** Double-click **OllamaUI** on your desktop

**Stop:** Close the browser window — services shut down, GPU freed

**Web interface:** `http://localhost:3000`

That's it. Really.

---

## 🗑️ Uninstall

**Copy this 👇 — Paste — Done.**

```bash
cd ollama-amd-plug-and-play
./uninstall_ollama.sh
```

- Removes Ollama service and binaries
- Removes Open WebUI Docker container and image
- Removes scripts and desktop shortcut
- **Keeps your models** in `~/.ollama` (delete manually if you want the space back)

---

## 🤖 Download a Model

```bash
docker exec ollama ollama pull MODEL_NAME
```

Wait, that's wrong — Ollama is native now. Use this instead:

```bash
ollama pull MODEL_NAME
```

**Examples:**

```bash
# Small & fast — low VRAM gang
ollama pull gemma3:4b

# Balanced — the Goldilocks zone
ollama pull gemma3:12b

# Large — you got the VRAM, flex it
ollama pull gemma4:26b

# Code wizard mode
ollama pull qwen2.5:7b

# European languages, surprisingly good
ollama pull mistral:7b
```

**List your models:**
```bash
ollama list
```

**Delete a model:**
```bash
ollama rm MODEL_NAME
```

### VRAM Guide

| Your VRAM | Recommended models |
|---|---|
| 4 GB | `gemma3:4b`, `phi3:mini` |
| 8 GB | `gemma3:12b`, `llama3:8b` |
| 12 GB | `gemma3:12b`, `mistral:12b` |
| 16 GB | `gemma4:26b`, `llama3:70b-q4` |
| 24 GB+ | Go nuts |

> 💡 Model too big for your VRAM? Ollama will spill into RAM automatically. Slower, but it runs. 

---

## 🔧 Useful Commands

**Check GPU is actually working (run during a generation):**
```bash
watch -n 1 ollama ps
# "GPU" in the PROCESSOR column = you're good
# "CPU" in the PROCESSOR column = something's wrong, check ~/install_ollama.log
```

**Restart when things feel weird:**
```bash
sudo systemctl restart ollama
docker restart open-webui
```

**View logs:**
```bash
journalctl -u ollama -n 50
docker logs open-webui
```

See **MEMO.txt** for the full command reference.

---

## 💬 Contributing

Found a bug? Want a feature? Something broke on your setup?
**Pull requests and issues welcome** — this is a community thing, not a one-person gate-keeping project.

Made by a fellow AMD Linux user who got tired of the setup dance. For everyone else who got tired too. 🤝

---

## 📄 License

MIT — use it, fork it, break it, make it better.
