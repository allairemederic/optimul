#!/usr/bin/env bash

# Charge le pilote QDMA et crée la file Memory-Mapped MM-0.
# À exécuter après la programmation du FPGA et du MicroBlaze.

set -euo pipefail

QDMA_BIN="/export/tmp/humblet/dma_ip_drivers-new2024/dma_ip_drivers/QDMA/linux-kernel/bin"
QDMA_DRIVER="${QDMA_BIN}/qdma-pf.ko"
DMA_CTL="${QDMA_BIN}/dma-ctl"

PCI_DEVICE="0000:01:00.0"
PCI_ADDRESS="01:00.0"
PCI_PATH="/sys/bus/pci/devices/${PCI_DEVICE}"

EXPECTED_VENDOR="0x10ee"
EXPECTED_DEVICE="0x902f"

QDMA_NAME="qdma01000"
QDMA_DEVICE="/dev/qdma01000-MM-0"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: this script must be executed with sudo." >&2
    exit 1
fi

if [[ ! -r "${QDMA_DRIVER}" ]]; then
    echo "Error: QDMA driver not found: ${QDMA_DRIVER}" >&2
    exit 1
fi

if [[ ! -x "${DMA_CTL}" ]]; then
    echo "Error: dma-ctl not found: ${DMA_CTL}" >&2
    exit 1
fi

echo "Configuring QDMA for the Transformer..."

# Retirer l'ancienne instance du pilote.
if lsmod | grep -q '^qdma_pf'; then
    echo "Removing qdma_pf..."
    rmmod qdma_pf
fi

# Retirer l'ancien périphérique PCIe.
if [[ -e "${PCI_PATH}/remove" ]]; then
    echo "Removing PCIe device ${PCI_DEVICE}..."
    printf '1\n' > "${PCI_PATH}/remove"
fi

# Charger le pilote avant le rescan afin que le probe soit automatique.
echo "Loading qdma_pf..."
insmod "${QDMA_DRIVER}"

# Réénumérer le périphérique PCIe.
echo "Rescanning PCIe..."
printf '1\n' > /sys/bus/pci/rescan

# Attendre l'apparition du périphérique.
for attempt in {1..10}; do
    if [[ -e "${PCI_PATH}" ]]; then
        break
    fi
    sleep 1
done

if [[ ! -e "${PCI_PATH}" ]]; then
    echo "Error: PCIe device ${PCI_DEVICE} was not detected." >&2
    exit 1
fi

lspci -nnk -s "${PCI_ADDRESS}"

# Vérifier que le bon périphérique a été trouvé.
vendor="$(<"${PCI_PATH}/vendor")"
device="$(<"${PCI_PATH}/device")"

if [[ "${vendor}" != "${EXPECTED_VENDOR}" ||
      "${device}" != "${EXPECTED_DEVICE}" ]]; then
    echo "Error: unexpected PCIe device ${vendor}:${device}." >&2
    exit 1
fi

# Attendre la fin du probe du pilote.
for attempt in {1..10}; do
    if [[ -d "${PCI_PATH}/qdma" &&
          -L "${PCI_PATH}/driver" ]]; then
        break
    fi
    sleep 1
done

if [[ ! -d "${PCI_PATH}/qdma" ]]; then
    echo "Error: qdma_pf did not initialize ${PCI_DEVICE}." >&2
    echo "Consult dmesg for the probe error." >&2
    exit 1
fi

echo "Setting qmax to 2..."
printf '2\n' > "${PCI_PATH}/qdma/qmax"

echo "Creating QDMA MM queue 0..."
"${DMA_CTL}" "${QDMA_NAME}" q add mode mm idx 0 dir bi
"${DMA_CTL}" "${QDMA_NAME}" q start idx 0 dir bi

for attempt in {1..5}; do
    if [[ -c "${QDMA_DEVICE}" ]]; then
        break
    fi
    sleep 1
done

if [[ ! -c "${QDMA_DEVICE}" ]]; then
    echo "Error: ${QDMA_DEVICE} was not created." >&2
    exit 1
fi

echo
echo "QDMA is ready:"
ls -l "${QDMA_DEVICE}"