# AMD AI Setup — Ollama + ComfyUI sur Ubuntu

Installation clé en main de **Ollama/Open WebUI** et **ComfyUI** avec accélération GPU AMD ROCm sur Ubuntu.

## Configuration testée

| Composant | Version |
|---|---|
| GPU | AMD Radeon RX 9070 XT (gfx1201) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.17.0-20-generic |
| ROCm | 7.2.0 |
| PyTorch | 2.13.0+rocm7.2 |
| Docker | 29.4.1 |

> Ce setup est conçu exclusivement pour les **GPU AMD** sous Ubuntu.

## Installation rapide

```bash
git clone https://github.com/miradorventus/amd-ai-setup.git
cd amd-ai-setup
chmod +x install.sh
./install.sh
```

## Installation individuelle

Ollama + Open WebUI :
```bash
cd ollama && ./install_ollama.sh
```

ComfyUI :
```bash
cd comfyui && ./install_comfyui.sh
```

## Licence
MIT
