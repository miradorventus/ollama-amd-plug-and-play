# 🚀 Ollama + Open WebUI — AMD Plug & Play

> **No terminal gymnastics. No dependency hell. Just vibes and working AI.**

Tired of spending your Saturday configuring PyTorch, Docker, ROCm, systemd and 47 browser tabs of Stack Overflow?
Yeah, same. That's why this exists.

**One click. Coffee-break install. Working AI on your AMD GPU.**

---

## 🎉 What's new — v2.0.0

- 🔥 **ROCm 7.2.2** — latest production stable, AMD official repos, RDNA4 ready
- 📁 **Custom install location** — pick where things live, with a clickable symlink to your models for easy file-manager access
- 🪟 **WebApp pattern** — OllamaUI now opens in its own dedicated window (like Mint's WebApp Manager apps), zero pollution of your personal Firefox profile
- 🎮 **Auto GPU split** — APU + dGPU setups (most modern Ryzens) are auto-configured to dedicate the dGPU to AI, freeing the iGPU for your desktop. **No more session crash on heavy models.**
- 🗂️ **Manage your models from the file manager** — drag-and-drop `.gguf` files, delete models, browse — all without sudo gymnastics
- 🚀 **Launcher renamed** — `ollamaui.sh` → `ollamaui-launcher.sh` for clarity
- ⚙️ **Self-detecting launcher** — works with default OR custom install paths automatically
- 🔧 **Hardened install** — verifies source files exist before copying, no silent failures

> ⚠️ **Breaking change from v1.x:** the launcher script was renamed. Existing users running v1.x will be silently migrated on next launch — no manual action needed.

---

## ✨ What you get

- 🖥️ **Desktop shortcut** — double-click. That's the whole workflow.
- 🤖 **Ollama** — native install (not Docker!) with full AMD ROCm acceleration
- 🌐 **Open WebUI** — the ChatGPT-style interface, running 100% on your machine
- 🪟 **Dedicated app window** — separate from your personal Firefox, won't mess with your tabs
- 🔒 **Fully offline** — your data doesn't leave your GPU
- ⚡ **On-demand** — services start when you click, stop when you close the browser
- 💾 **VRAM friendly** — models auto-unload after 5 minutes of silence
- 🔋 **Power efficient** — nothing runs at boot, no wasted wattage

---

## 🖥️ Requirements

| Component | Requirement |
|---|---|
| **OS** | Ubuntu 24.04 LTS **or** Linux Mint 22.x (XFCE/Cinnamon) |
| **GPU** | AMD with ROCm support (RX 6000 series and newer) |
| **RAM** | 16 GB minimum |
| **Storage** | 20 GB free minimum |
| **Internet** | For initial setup only (then offline forever) |

> ⚠️ **RDNA4 gang (RX 9070 / 9070 XT):** `HSA_OVERRIDE_GFX_VERSION=12.0.1` is already wired up. You're welcome.

> 💡 **APU + dGPU users (most Ryzen 7000+/8000+/9000+):** the launcher detects your dual-GPU setup automatically and tells Ollama to use only the dedicated GPU. **Goodbye, mid-generation session crashes.**

---

## 📦 Installation

**Copy 👇 — Paste — Grab a coffee ☕**

```bash
git clone https://github.com/miradorventus/ollama-amd-plug-and-play.git
cd ollama-amd-plug-and-play
chmod +x install_ollama.sh
./install_ollama.sh
```

The installer is **GUI all the way** — no scary terminal stuff:

### Step 0 — Welcome
Adaptive popup that scans your system and tells you exactly:
- What's already installed (kept as-is)
- What's missing (will be installed)
- Total download size
- Whether a reboot will be needed

You can cancel here. No hard feelings.

### Step 0.5 — Install location *(new in v2.0.0)*
Pick where to install:
- ✅ **Default** — `~/.ollamaui/` (hidden, standard Linux convention)
- 📁 **Custom location** — pick your parent folder (e.g., `~/AI-Tools/`), the installer creates `<your-folder>/ollamaui/` for scripts and `<your-folder>/ollama-models` as a clickable shortcut to your model storage
- ← **Back** — change your mind, go back to welcome

### Step 1 — Dependencies *(if needed)*
Installs missing pieces from **official repos only**:
- 🟦 **Docker** — Ubuntu/Mint apt
- 🔴 **ROCm 7.2.2** — `repo.radeon.com` (AMD official)
- ⚙️ **curl** — Ubuntu/Mint apt

If ROCm is fresh, the script will offer a reboot before continuing (auto-resumes after reboot).

### Step 2 — Ollama
Three choices, you pick:
- ✅ **Install fresh** — official `ollama.com` installer
- 📂 **Import existing** — point to your existing Ollama folder, models stay yours
- ❌ **Stop install** — bail out cleanly with rollback

### Step 3 — Open WebUI + finalize
Three choices again:
- ✅ **Install fresh** — official `ghcr.io/open-webui` Docker image
- 🌐 **I have it elsewhere** — paste your existing WebUI URL, we just create the shortcut
- ❌ **Stop install** — full rollback

### Step 4 — Done
"Launch now?" — click and start chatting.

---

## 🎮 Daily Usage

**Start:** Double-click **OllamaUI** on your desktop

**Stop:** Close the browser window — services shut down, GPU freed

**Web interface:** `http://127.0.0.1:3000`

**Already running?** Click the desktop icon again — it gracefully tells you to look at your existing window.

That's it. Really.

---

## 📁 Manage Your Models from the File Manager

If you chose a custom install location, you have a clickable `ollama-models` shortcut next to your `ollamaui/` folder. Open it in Thunar / Nautilus / Caja, and you can:

- 📥 **Drag-and-drop** custom `.gguf` files into the right folder
- 🗑️ **Delete models** without sudo gymnastics
- 📂 **Browse** what's actually on disk
- ✏️ **Rename / organize** as you wish

The shortcut is a symlink to the real storage at `/usr/share/ollama/.ollama/models`. The installer set up the right permissions so your user can write there safely.

> 🛡️ **Doesn't break anything.** Ollama keeps writing to its standard location. The shortcut is just a window into it.

---

## 🛠️ Smart Repair

Things break sometimes. Networks fail. Updates conflict. Files get deleted.

If something's wrong with your install, **just relaunch the OllamaUI icon**. The launcher silently checks all components and pops up a clear list of what's missing, with a **"Repair now"** button that runs the installer to fix only what's broken. Your conversations and models stay safe.

---

## 👨‍🔬 Power User Shortcuts

Already have Ollama running with custom models? Don't reinstall — **import**:

1. Run `./install_ollama.sh`
2. At Step 2, choose **"Import existing"**
3. Point to your Ollama folder (`~/.ollama` or `/usr/share/ollama/.ollama`)
4. Done — your models, your config, plus our launcher

Already have Open WebUI elsewhere (LAN, another machine, custom port)?

1. Run `./install_ollama.sh` (or just the launcher)
2. At Step 3, choose **"I have it elsewhere"**
3. Paste your URL (`http://192.168.1.50:3000` or whatever)
4. Desktop shortcut created — points directly to your existing instance

---

## 🗑️ Uninstall

**Copy 👇 — Paste — Done.**

```bash
cd ollama-amd-plug-and-play
./uninstall_ollama.sh
```

- ✅ Removes Ollama service and binaries
- ✅ Removes Open WebUI Docker container and image
- ✅ Removes launch scripts and desktop shortcut
- ✅ Removes our UFW firewall rule
- 💾 **Keeps your models** in `/usr/share/ollama/.ollama` (delete manually if you want the space back)
- 💾 **Keeps your conversations** in the Docker volume `open-webui` (delete with `docker volume rm open-webui` if needed)

---

## 🤖 Download a Model

```bash
ollama pull MODEL_NAME
```

Or download directly from the WebUI: **Settings → Models → tap a name**.

**Examples:**

```bash
# Small & fast — low VRAM gang
ollama pull gemma3:4b

# Balanced — the Goldilocks zone
ollama pull gemma3:12b

# Large — you got the VRAM, flex it
ollama pull gemma4:26b

# Code wizard mode
ollama pull qwen2.5-coder:14b

# Surprisingly good for European languages
ollama pull mistral-nemo:latest
```

**List models:**
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

> 💡 Model too big for your VRAM? Ollama spills into RAM automatically. Slower, but it runs.

---

## 🔧 Useful Commands

**Check GPU is actually working (during a generation):**
```bash
watch -n 1 ollama ps
# 100% GPU in the PROCESSOR column = you're good
# Mostly CPU = model too big for VRAM, or check ~/.ollamaui/install_ollama.log
```

**Restart when things feel weird:**
```bash
sudo systemctl restart ollama
docker restart open-webui
```

**View logs:**
```bash
# Install log (default location)
cat ~/.ollamaui/install_ollama.log

# Or your custom location
cat ~/AI-Tools/ollamaui/install_ollama.log

# Ollama service
journalctl -u ollama -n 50

# Open WebUI
docker logs open-webui --tail 50
```

**Verify GPU acceleration is enabled:**
```bash
sudo journalctl -u ollama -n 100 | grep -iE "rocm|vram|gfx"
# You should see ROCm mentioned, with VRAM size and your GPU's gfx target
```

**Multi-GPU? Check which GPU Ollama uses:**
```bash
sudo cat /etc/systemd/system/ollama.service.d/override.conf | grep HIP
# HIP_VISIBLE_DEVICES=0 means it uses your first dedicated GPU (correct for APU+dGPU setups)
```

---

## 🙏 Sources Used (all official)

| Component | Source |
|---|---|
| Ollama | https://ollama.com/install.sh |
| Open WebUI | `ghcr.io/open-webui/open-webui` (GitHub) |
| ROCm 7.2.2 | https://repo.radeon.com (AMD official) |
| Docker | Ubuntu/Mint apt repos |

No PPA. No fork. No mirror. Just trust + officialness.

---

## 💬 Contributing

Found a bug? Tested on a setup we don't list? Want a feature?
**Issues and PRs welcome** — this is a community thing, not a one-person gate-keeping project.

Made by a fellow AMD Linux user who got tired of the setup dance. For everyone else who got tired too. 🤝

---

## 📄 License

MIT — use it, fork it, break it, make it better.
