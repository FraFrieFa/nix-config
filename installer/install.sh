#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/FraFrieFa/nix-config.git"
EMBEDDED_CONFIG="/etc/nix-config"
INSTALL_CONFIG="/mnt/etc/nixos"

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

CONFIG_SOURCE="$EMBEDDED_CONFIG"
TEMP_CLONE=""

if ping -c1 -W2 github.com &>/dev/null 2>&1; then
  echo -e "${GREEN}Network available${NC}"
  read -p "Pull latest config from GitHub? [y/N]: " UPDATE_CHOICE
  if [[ "${UPDATE_CHOICE,,}" == "y" ]]; then
    TEMP_CLONE=$(mktemp -d)
    echo -e "${CYAN}Cloning latest config...${NC}"
    git clone --depth 1 "$REPO_URL" "$TEMP_CLONE" 2>/dev/null
    CONFIG_SOURCE="$TEMP_CLONE"
  fi
else
  echo -e "${CYAN}No network — using embedded config${NC}"
fi

mapfile -t HOSTS < <(nix flake show --json --no-update-lock-file "$CONFIG_SOURCE" 2>/dev/null \
  | jq -r '.nixosConfigurations | keys[] | select(. != "installer")')

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
parted -s "$DISK" -- mkpart boot fat32 1MiB 2GiB
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart cryptroot 2GiB 100%

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

echo -e "${CYAN}Formatting EFI partition (label: BOOT)...${NC}"
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
  --batch-mode \
  "$PART2"

echo -e "\n${CYAN}Opening encrypted partition...${NC}"
cryptsetup open "$PART2" cryptroot

echo -e "${CYAN}Formatting root filesystem (label: nixos)...${NC}"
mkfs.ext4 -L nixos /dev/mapper/cryptroot

echo -e "${CYAN}Mounting filesystems...${NC}"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$PART1" /mnt/boot

echo -e "${CYAN}Placing configuration at /root/nix-config...${NC}"
mkdir -p /mnt/root
chmod 700 /mnt/root

if [[ -n "$TEMP_CLONE" ]]; then
  cp -r "$TEMP_CLONE/." "$INSTALL_CONFIG"
  rm -rf "$TEMP_CLONE"
else
  cp -r "$EMBEDDED_CONFIG/." "$INSTALL_CONFIG"
fi

echo -e "\n${CYAN}${BOLD}Installing NixOS...${NC}\n"

nixos-install --flake "$INSTALL_CONFIG#$HOST"

mkdir -p /mnt/etc
ln -sf /root/nix-config /mnt/etc/nixos

print_header
echo -e "${CYAN}${BOLD}Set user passwords:${NC}\n"

for USER in $(nixos-enter --root /mnt -c 'getent passwd | awk -F: "$3 >= 1000 && $3 < 65534 {print $1}"' 2>/dev/null); do
  echo -e "Password for ${BOLD}$USER${NC}:"
  nixos-enter --root /mnt -c "passwd $USER"
  echo ""
done

print_header
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "  /etc/nixos → /root/nix-config (nixos-rebuild switch works as usual)"
if [[ -z "$TEMP_CLONE" ]]; then
  echo -e "  Config was installed from the embedded ISO snapshot."
  echo -e "  To track changes: ${BOLD}cd /etc/nixos && git init && git remote add origin $REPO_URL${NC}"
fi
echo ""
echo -e "  Reboot: ${BOLD}reboot${NC}"
echo ""
read -p "Press Enter to continue..."
