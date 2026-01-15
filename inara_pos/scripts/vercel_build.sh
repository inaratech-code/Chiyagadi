#!/usr/bin/env bash
set -euo pipefail

echo "==> Vercel Flutter build script"

# Ensure git can write a global config in this environment (Vercel can run as root
# and $HOME may not be writable/persistent).
export HOME="${HOME:-$PWD}"
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}"

# Install Flutter SDK (stable) if not already present.
# We install into a local folder so Vercel caching (if enabled) can reuse it.
FLUTTER_DIR="${FLUTTER_DIR:-.flutter}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.19.6}"  # Dart 3.3.x, compatible with sdk >=3.0.0 <4.0.0
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

if [[ ! -d "${FLUTTER_DIR}/flutter" ]]; then
  echo "==> Downloading Flutter ${FLUTTER_VERSION}..."
  mkdir -p "${FLUTTER_DIR}"
  curl -L "${FLUTTER_URL}" -o "${FLUTTER_DIR}/${FLUTTER_ARCHIVE}"
  tar -xf "${FLUTTER_DIR}/${FLUTTER_ARCHIVE}" -C "${FLUTTER_DIR}"
  rm -f "${FLUTTER_DIR:?}/${FLUTTER_ARCHIVE}"
else
  echo "==> Flutter already present at ${FLUTTER_DIR}/flutter"
fi

export PATH="$PWD/${FLUTTER_DIR}/flutter/bin:$PATH"

# Vercel sometimes runs builds in a container/user setup that triggers Git's
# "dubious ownership" protection. Flutter SDK is a git repo internally, so we
# must mark it as safe or Flutter can't determine its version (shows 0.0.0-unknown).
git config --global --add safe.directory "$PWD/${FLUTTER_DIR}/flutter" || true
git config --global --add safe.directory "$PWD/${FLUTTER_DIR}/flutter/.git" || true

flutter --version

echo "==> Flutter config"
flutter config --enable-web

echo "==> Pub get"
flutter pub get

echo "==> Build web (release)"
flutter build web --release

echo "==> Done. Output is build/web"

