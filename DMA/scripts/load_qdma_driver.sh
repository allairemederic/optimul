#!/usr/bin/env bash

set -e

QDMA_BIN="/export/tmp/humblet/dma_ip_drivers-new2024/dma_ip_drivers/QDMA/linux-kernel/bin"
DMA_CTL="${QDMA_BIN}/dma-ctl"

PCI_DEVICE="0000:01:00.0"
PCI_PATH="/sys/bus/pci/devices/${PCI_DEVICE}"

QDMA_NAME="qdma01000"
QDMA_DEVICE="/dev/qdma01000-MM-0"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: run this script with sudo." >&2
    exit 1
fi

echo "Configuring QDMA..."

# Le pilote doit déjà être chargé.
if [[ ! -d /sys/module/qdma_pf ]]; then
    echo "Error: qdma_pf is not loaded." >&2
    exit 1
fi

echo "qdma_pf is loaded."

# Retirer l'ancienne entrée PCIe
if [[ -e "${PCI_PATH}/remove" ]]; then
    echo "Removing PCIe device ${PCI_DEVICE}..."
    echo 1 > "${PCI_PATH}/remove"
    sleep 1
fi

# Redétecter le périphérique PCIe.
echo "Rescanning PCIe..."
echo 1 > /sys/bus/pci/rescan
sleep 2

# Vérifier que le QDMA est réapparu.
if [[ ! -e "${PCI_PATH}" ]]; then
    echo "Error: PCIe device ${PCI_DEVICE} was not detected." >&2
    exit 1
fi

lspci -nnk -s 01:00.0

# Vérifier que le pilote a initialisé le QDMA.
if [[ ! -d "${PCI_PATH}/qdma" ]]; then
    echo "Error: QDMA was not initialized." >&2
    exit 1
fi

# Ne pas recréer la file si elle existe déjà.
if [[ -c "${QDMA_DEVICE}" ]]; then
    echo "QDMA is already ready:"
    ls -l "${QDMA_DEVICE}"
    exit 0
fi

# Vérifier dma-ctl seulement après le rescan.
if [[ ! -x "${DMA_CTL}" ]]; then
    echo "Error: dma-ctl not found: ${DMA_CTL}" >&2
    exit 1
fi

echo "Setting qmax to 2..."
echo 2 > "${PCI_PATH}/qdma/qmax"

echo "Creating MM queue 0..."
"${DMA_CTL}" "${QDMA_NAME}" q add mode mm idx 0 dir bi
"${DMA_CTL}" "${QDMA_NAME}" q start idx 0 dir bi

echo
echo "QDMA is ready:"
ls -l "${QDMA_DEVICE}"