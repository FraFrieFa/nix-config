#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/FraFrieFa/nix-config.git"
CONFIG_PATH="/mnt/etc/nixos"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔════════════════════════════════════════╗"
  echo "║       NixOS Flake Installer            ║"
  echo "╚════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_header

echo -e "${CYAN}Waiting for network...${NC}"
for i in {1..30}; do
  if ping -c1 github.com &>/dev/null; then
    echo -e "${GREEN}Network ready${NC}"
    break
  fi
  sleep 1
done

TEMP_REPO=$(mktemp -d)
echo -e "\n${CYAN}Fetching configuration...${NC}"
git clone --depth 1 "$REPO_URL" "$TEMP_REPO" 2>/dev/null

cd "$TEMP_REPO"
mapfile -t HOSTS < <(nix flake show --json 2>/dev/null | jq -r '.nixosConfigurations | keys[] | select(. != "installer")')

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  echo -e "${RED}No hosts found in flake${NC}"
  exit 1
fi

print_header
echo -e "${BOLD}Select host to install:${NC}\n"
for i in "${!HOSTS[@]}"; do
  echo "  $((i+1))) ${HOSTS[$i]}"
done
echo ""

while true; do
  read -p "Enter number [1-${#HOSTS[@]}]: " HOST_NUM
  if [[ "$HOST_NUM" =~ ^[0-9]+$ ]] && ((HOST_NUM >= 1 && HOST_NUM <= ${#HOSTS[@]})); then
    HOST="${HOSTS[$((HOST_NUM-1))]}"
    break
  fi
  echo -e "${RED}Invalid selection${NC}"
done

echo -e "\n${GREEN}Selected: ${BOLD}$HOST${NC}\n"

print_header
echo -e "${BOLD}Host:${NC} $HOST\n"
echo -e "${BOLD}Available disks:${NC}\n"
lsblk -d -o NAME,SIZE,MODEL | grep -v -E "^loop|^sr|^ram"
echo ""

while true; do
  read -p "Enter disk (e.g., nvme0n1, sda): " DISK_NAME
  DISK="/dev/$DISK_NAME"
  if [[ -b "$DISK" ]]; then
    break
  fi
  echo -e "${RED}Disk not found${NC}"
done

echo ""
echo -e "${RED}${BOLD}WARNING: This will ERASE ${DISK}${NC}"
echo ""
read -p "Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted"
  exit 1
fi

print_header
echo -e "${CYAN}Partitioning ${DISK}...${NC}"

wipefs -af "$DISK"
parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart ESP fat32 1MiB 2GiB
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart primary 2GiB 100%

if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
  PART1="${DISK}p1"
  PART2="${DISK}p2"
else
  PART1="${DISK}1"
  PART2="${DISK}2"
fi

sleep 1
partprobe "$DISK"
sleep 1

echo -e "${CYAN}Formatting EFI partition...${NC}"
mkfs.fat -F 32 -n BOOT "$PART1"

echo -e "\n${CYAN}Setting up LUKS2 encryption...${NC}"
echo -e "${BOLD}Enter disk encryption passphrase:${NC}"

cryptsetup luksFormat --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --hash sha256 \
  --pbkdf argon2id \
  --pbkdf-memory 1048576 \
  --pbkdf-parallel 4 \
  --iter-time 3000 \
  --label cryptroot \
  --batch-mode \
  "$PART2"

echo -e "\n${CYAN}Opening encrypted partition...${NC}"
cryptsetup open "$PART2" cryptroot

echo -e "${CYAN}Formatting root filesystem...${NC}"
mkfs.ext4 -L nixos /dev/mapper/cryptroot

echo -e "${CYAN}Mounting filesystems...${NC}"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$PART1" /mnt/boot

echo -e "${CYAN}Cloning configuration...${NC}"
mkdir -p /mnt/etc
rm -rf "$CONFIG_PATH"
git clone "$REPO_URL" "$CONFIG_PATH"

echo -e "${CYAN}Generating hardware configuration...${NC}"

LUKS_UUID=$(blkid -s UUID -o value "$PART2")
BOOT_UUID=$(blkid -s UUID -o value "$PART1")

cat > "$CONFIG_PATH/hosts/$HOST/hardware.nix" << EOF
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
  };

  boot.initrd.luks.devices."cryptroot" = {
    device        = "/dev/disk/by-uuid/$LUKS_UUID";
    allowDiscards = true;
    bypassWorkqueues = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/$BOOT_UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF

echo -e "\n${CYAN}${BOLD}Installing NixOS...${NC}\n"

nixos-install --flake "$CONFIG_PATH#$HOST" --no-root-passwd

rm -rf "$TEMP_REPO"

print_header
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Set user password: ${BOLD}nixos-enter --root /mnt -c 'passwd fabius'${NC}"
echo -e "  2. Reboot: ${BOLD}reboot${NC}"
echo ""
read -p "Press Enter to continue..."
