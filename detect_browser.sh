#!/bin/bash
# Détecte le navigateur par défaut et retourne la commande adaptée

DEFAULT=$(xdg-settings get default-web-browser 2>/dev/null)

case "$DEFAULT" in
  *firefox*)
    BROWSER="firefox"
    PROFILE_ARG="--no-remote --profile"
    ;;
  *microsoft-edge*|*edge*)
    BROWSER="microsoft-edge"
    PROFILE_ARG="--profile-directory="
    ;;
  *google-chrome*|*chrome*)
    BROWSER="google-chrome"
    PROFILE_ARG="--profile-directory="
    ;;
  *chromium*)
    BROWSER="chromium-browser"
    PROFILE_ARG="--profile-directory="
    ;;
  *)
    # Fallback — ouvre sans profil dédié
    BROWSER="xdg-open"
    PROFILE_ARG=""
    ;;
esac

echo "$BROWSER|$PROFILE_ARG"
