# 🚀 Ollama + Open WebUI — AMD Plug & Play

> **No terminal gymnastics. No dependency hell. Just vibes and working AI.**

Tired of spending your Saturday configuring PyTorch, Docker, ROCm, systemd and 47 browser tabs of Stack Overflow?
Yeah, same. That's why this exists.

**One click. Coffee-break install. Working AI on your AMD GPU.**

---

## 🎉 What's new — v1.5.0

- 🐧 **Linux Mint support** — XFCE & Cinnamon tested, Ubuntu compat preserved
- 🎨 **Brand new install UX** — adaptive welcome popup that detects your existing setup
- 📦 **Power user mode** — already have Ollama or WebUI elsewhere? Just import them
- 🛡️ **Smart rollback** — change your mind mid-install? Click "Stop install" and the script cleans up everything
- 🔧 **Self-repair** — broken something? Re-launch the icon, the script detects what's missing and proposes a fix
- 🔥 **UFW auto-config** — no more "Connection error" on Mint (Docker subnet → port 11434)
- ✅ **Verified ROCm install** — fails fast and clear if AMD repos can't be reached
- 💡 **Source transparency** — every popup tells you exactly what's installed, from where, and why

---

## ✨ What you get

- 🖥️ **Desktop shortcut** — double-click. That's the whole workflow.
- 🤖 **Ollama** — native install (not Docker!) with full AMD ROCm acceleration
- 🌐 **Open WebUI** — the ChatGPT-style interface, running 100% on your machine
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

### Step 1 — Dependencies *(if needed)*
Installs missing pieces from **official repos only**:
- 🟦 **Docker** — Ubuntu/Mint apt
- 🔴 **ROCm 6.3** — `repo.radeon.com` (AMD official)
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
- 💾 **Keeps your models** in `~/.ollama` (delete manually if you want the space back)
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
ollama pull qwen2.5:7b

# Surprisingly good for European languages
ollama pull mistral:7b
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
# 100% CPU = something's wrong, check ~/install_ollama.log
```

**Restart when things feel weird:**
```bash
sudo systemctl restart ollama
docker restart open-webui
```

**View logs:**
```bash
# Install log
cat ~/install_ollama.log

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

See **MEMO.txt** for the full command reference.

---

## 🙏 Sources Used (all official)

| Component | Source |
|---|---|
| Ollama | https://ollama.com/install.sh |
| Open WebUI | `ghcr.io/open-webui/open-webui` (GitHub) |
| ROCm 6.3 | https://repo.radeon.com (AMD official) |
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
