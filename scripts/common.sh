#!/usr/bin/env bash
# Common configuration and helper functions for RHDH scripts

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.crc/bin:${PATH}"

if [[ -z "${KUBECONFIG:-}" ]]; then
    if [[ -f "${HOME}/.crc/machines/crc/kubeconfig" ]]; then
        export KUBECONFIG="${HOME}/.crc/machines/crc/kubeconfig"
    elif [[ -f "${HOME}/.crc/cache/crc_vfkit_4.22.14_arm64/kubeconfig" ]]; then
        export KUBECONFIG="${HOME}/.crc/cache/crc_vfkit_4.22.14_arm64/kubeconfig"
    fi
fi
