#!/bin/bash
# Detect default browser and return the adapted command
DEFAULT=$(xdg-settings get default-web-browser 2>/dev/null)

case "$DEFAULT" in
  *firefox*)       BROWSER="firefox";         PROFILE_ARG="--no-remote --profile" ;;
  *edge*)          BROWSER="microsoft-edge";  PROFILE_ARG="--profile-directory=" ;;
  *chrome*)        BROWSER="google-chrome";   PROFILE_ARG="--profile-directory=" ;;
  *chromium*)      BROWSER="chromium-browser";PROFILE_ARG="--profile-directory=" ;;
  *)               BROWSER="xdg-open";        PROFILE_ARG="" ;;
esac

echo "$BROWSER|$PROFILE_ARG"
