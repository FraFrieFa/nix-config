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
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "╔════════════════════════════════════════╗"
  echo "║       NixOS Flake Installer            ║"
  echo "╚════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_header

CONFIG_SOURCE="${CONFIG_SOURCE_OVERRIDE:-$EMBEDDED_CONFIG}"
TEMP_CLONE="${TEMP_CLONE_OVERRIDE:-}"

have_github_access() {
  git ls-remote --exit-code "$REPO_URL" HEAD &>/dev/null
}

wait_for_github_access() {
  echo -e "${CYAN}Waiting briefly for network...${NC}"
  for _ in {1..8}; do
    if have_github_access; then
      return 0
    fi
    sleep 1
  done

  while true; do
    echo ""
    echo -e "${CYAN}GitHub is not reachable yet.${NC}"
    echo "Press Enter to retry, type 'nmtui' to configure networking, or type 'skip' to use the embedded config."
    read -r NETWORK_ACTION

    case "${NETWORK_ACTION,,}" in
      skip)
        return 1
        ;;
      nmtui)
        if command -v nmtui &>/dev/null; then
          nmtui
        else
          echo -e "${RED}nmtui is not available in this environment${NC}"
        fi
        ;;
    esac

    if have_github_access; then
      return 0
    fi
  done
}

partition_disk() {
  local disk="$1"

  echo ""
  echo -e "${RED}${BOLD}WARNING: This will ERASE ${disk}${NC}"
  echo ""
  read -p "Type 'yes' to confirm: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted"
    exit 1
  fi

  print_header
  echo -e "${CYAN}Partitioning ${disk}...${NC}"

  wipefs -af "$disk"
  parted -s "$disk" -- mklabel gpt
  parted -s "$disk" -- mkpart boot fat32 1MiB 2GiB
  parted -s "$disk" -- set 1 esp on
  parted -s "$disk" -- mkpart cryptroot 2GiB 100%

  if [[ "$disk" == *"nvme"* ]] || [[ "$disk" == *"mmcblk"* ]]; then
    BOOT_PART="${disk}p1"
    ROOT_PART="${disk}p2"
  else
    BOOT_PART="${disk}1"
    ROOT_PART="${disk}2"
  fi

  sleep 1
  partprobe "$disk"
  sleep 1
}

list_target_users() {
  awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|noshell)/ { print $1 }' /mnt/etc/passwd 2>/dev/null || true
}

select_install_disk() {
  local disk

  print_header
  echo -e "${BOLD}Available disks:${NC}\n"
  lsblk -d -o NAME,SIZE,MODEL | grep -v -E "^loop|^sr|^ram"
  echo ""

  while true; do
    read -p "Enter disk to erase completely (e.g., nvme0n1, sda): " DISK_NAME
    disk="/dev/$DISK_NAME"
    if [[ -b "$disk" ]]; then
      partition_disk "$disk"
      return 0
    fi
    echo -e "${RED}Disk not found${NC}"
  done
}

if [[ -n "${CONFIG_SOURCE_OVERRIDE:-}" ]]; then
  echo -e "${GREEN}Continuing with freshly pulled config${NC}"
else
  read -p "Pull latest config from GitHub? [y/N]: " UPDATE_CHOICE
  if [[ "${UPDATE_CHOICE,,}" == "y" ]]; then
    if wait_for_github_access; then
      TEMP_CLONE=$(mktemp -d)
      echo -e "${CYAN}Cloning latest config...${NC}"
      if git clone --depth 1 "$REPO_URL" "$TEMP_CLONE"; then
        CONFIG_SOURCE="$TEMP_CLONE"
        echo -e "${GREEN}Using freshly cloned config${NC}"

        if [[ -x "$TEMP_CLONE/installer/install.sh" ]] && [[ "${INSTALLER_REEXECED:-0}" != "1" ]]; then
          echo -e "${CYAN}Restarting installer from the freshly pulled repo...${NC}"
          exec env \
            INSTALLER_REEXECED=1 \
            CONFIG_SOURCE_OVERRIDE="$TEMP_CLONE" \
            TEMP_CLONE_OVERRIDE="$TEMP_CLONE" \
            "$TEMP_CLONE/installer/install.sh"
        fi
      else
        rm -rf "$TEMP_CLONE"
        TEMP_CLONE=""
        CONFIG_SOURCE="$EMBEDDED_CONFIG"
        echo -e "${RED}Clone failed — falling back to embedded config${NC}"
      fi
    else
      echo -e "${CYAN}Using embedded config${NC}"
    fi
  else
    echo -e "${CYAN}Using embedded config${NC}"
  fi
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
select_install_disk

echo -e "${CYAN}Formatting EFI partition (label: BOOT)...${NC}"
mkfs.fat -F 32 -n BOOT "$BOOT_PART"

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
  "$ROOT_PART"

echo -e "\n${CYAN}Opening encrypted partition...${NC}"
cryptsetup open "$ROOT_PART" cryptroot

echo -e "${CYAN}Formatting root filesystem (label: nixos)...${NC}"
mkfs.ext4 -L nixos /dev/mapper/cryptroot

echo -e "${CYAN}Mounting filesystems...${NC}"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount -o umask=077 "$BOOT_PART" /mnt/boot

echo -e "${CYAN}Placing configuration at /etc/nixos...${NC}"
mkdir -p /mnt/etc

if [[ -n "$TEMP_CLONE" ]]; then
  cp -r "$TEMP_CLONE/." "$INSTALL_CONFIG"
  rm -rf "$TEMP_CLONE"
else
  cp -r "$EMBEDDED_CONFIG/." "$INSTALL_CONFIG"
fi

echo -e "\n${CYAN}${BOLD}Installing NixOS...${NC}\n"

nixos-install --no-root-passwd --flake "$INSTALL_CONFIG#$HOST"

TARGET_OWNER=$(list_target_users | head -n1)
if [[ -n "$TARGET_OWNER" ]]; then
  echo -e "\n${CYAN}Adjusting /etc/nixos ownership for ${TARGET_OWNER}:nixos-config...${NC}\n"
  nixos-enter --root /mnt -c "chown -R ${TARGET_OWNER}:nixos-config /etc/nixos \
    && chmod -R u+rwX,g+rwX /etc/nixos \
    && find /etc/nixos -type d -exec chmod g+s {} +"
else
  echo -e "\n${RED}Could not determine a normal user for /etc/nixos ownership; leaving root ownership in place${NC}\n"
fi

print_header
echo -e "${CYAN}${BOLD}Set user passwords:${NC}\n"

for USER in $(list_target_users); do
  echo -e "Password for ${BOLD}$USER${NC}:"
  nixos-enter --root /mnt -c "passwd $USER"
  echo ""
done

print_header
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "  Config is installed directly in ${BOLD}/etc/nixos${NC}"
if [[ -z "$TEMP_CLONE" ]]; then
  echo -e "  Config was installed from the embedded ISO snapshot."
  echo -e "  To track changes: ${BOLD}cd /etc/nixos && git init && git remote add origin $REPO_URL${NC}"
fi
echo ""
echo -e "  Reboot: ${BOLD}reboot${NC}"
echo ""
read -p "Press Enter to continue..."
