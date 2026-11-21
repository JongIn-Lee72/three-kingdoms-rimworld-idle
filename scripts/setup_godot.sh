#!/usr/bin/env bash
# File: scripts/setup_godot.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1-stable}"
INSTALL_DIR="${HOME}/.local/bin"
CACHE_DIR="${HOME}/.cache/godot_downloads"

mkdir -p "${INSTALL_DIR}" "${CACHE_DIR}"

if [[ "${GODOT_VERSION}" == "4.4.1-stable" ]]; then
    EXPECTED_SHA512="ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e"
elif [[ "${GODOT_VERSION}" == "4.7.2-stable" ]]; then
    EXPECTED_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
else
    echo "ERROR: Unsupported GODOT_VERSION=${GODOT_VERSION}" >&2
    exit 1
fi

ZIP_NAME="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
BIN_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
ZIP_PATH="${CACHE_DIR}/${ZIP_NAME}"
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP_NAME}"

if [[ ! -x "${INSTALL_DIR}/godot" ]] || ! "${INSTALL_DIR}/godot" --version 2>/dev/null | grep -q "^${GODOT_VERSION%-stable}"; then
    echo "[setup_godot] Downloading ${DOWNLOAD_URL} ..."
    rm -f "${ZIP_PATH}"
    if ! curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_URL}" -o "${ZIP_PATH}"; then
        rm -f "${ZIP_PATH}"
        echo "ERROR: Failed to download ${DOWNLOAD_URL}" >&2
        exit 1
    fi
    if ! echo "${EXPECTED_SHA512}  ${ZIP_PATH}" | sha512sum -c -; then
        rm -f "${ZIP_PATH}"
        echo "ERROR: SHA-512 checksum verification failed for ${ZIP_PATH}" >&2
        exit 1
    fi
    unzip -q -o "${ZIP_PATH}" -d "${CACHE_DIR}"
    chmod +x "${CACHE_DIR}/${BIN_NAME}"
    mv "${CACHE_DIR}/${BIN_NAME}" "${INSTALL_DIR}/godot"
    ln -sf "${INSTALL_DIR}/godot" "${INSTALL_DIR}/godot4"
    rm -f "${ZIP_PATH}"
fi

export PATH="${INSTALL_DIR}:${PATH}"
echo "[setup_godot] Installed Godot version: $(godot --version)"
