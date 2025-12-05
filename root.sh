#!/bin/sh

ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
max_retries=10
timeout=30
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      Foxytoux INSTALLER"
  echo "#"
  echo "#                           Copyright (C) 2024, RecodeStudios.Cloud"
  echo "#"
  echo "#"
  echo "#######################################################################################"

  echo "Installing Ubuntu 20.04 LTS (Focal Fossa)..."
  
  # Попробуем разные зеркала по порядку
  MIRRORS="
  http://archive.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz
  http://mirrors.edge.kernel.org/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz
  http://ftp.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz
  "
  
  DOWNLOAD_SUCCESS=0
  for mirror in $MIRRORS; do
    echo "Trying mirror: $mirror"
    if wget --tries=3 --timeout=30 --no-hsts --show-progress -O /tmp/rootfs.tar.gz "$mirror"; then
      echo "Download successful!"
      DOWNLOAD_SUCCESS=1
      break
    else
      echo "Mirror failed, trying next..."
      rm -f /tmp/rootfs.tar.gz
      sleep 2
    fi
  done
  
  if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
    echo "Error: All mirrors failed!"
    echo "Trying Cloudflare mirror as last resort..."
    if wget --tries=3 --timeout=30 --no-hsts --show-progress -O /tmp/rootfs.tar.gz \
      "https://cloud-images.ubuntu.com/base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz"; then
      DOWNLOAD_SUCCESS=1
    fi
  fi
  
  if [ $DOWNLOAD_SUCCESS -eq 1 ]; then
    echo "Extracting Ubuntu rootfs..."
    tar -xzf /tmp/rootfs.tar.gz -C $ROOTFS_DIR
    echo "Ubuntu installation completed!"
  else
    echo "Fatal: Could not download Ubuntu. Check your internet connection."
    exit 1
  fi
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "Setting up PRoot environment..."
  
  mkdir -p $ROOTFS_DIR/usr/local/bin
  
  # Скачиваем PRoot с нескольких возможных источников
  PROOT_URLS="
  https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-${ARCH}-static
  https://github.com/proot-me/PRoot/releases/download/v5.1.0/proot-v5.1.0-${ARCH}-static
  "
  
  PROOT_DOWNLOADED=0
  for url in $PROOT_URLS; do
    echo "Downloading PRoot from: $url"
    if wget --tries=3 --timeout=30 --no-hsts --show-progress -O $ROOTFS_DIR/usr/local/bin/proot "$url"; then
      PROOT_DOWNLOADED=1
      break
    fi
  done
  
  if [ $PROOT_DOWNLOADED -eq 0 ]; then
    echo "Trying alternative PRoot source..."
    # Альтернативный источник
    if wget --tries=3 --timeout=30 --no-hsts --show-progress -O $ROOTFS_DIR/usr/local/bin/proot \
      "https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${ARCH}"; then
      PROOT_DOWNLOADED=1
    fi
  fi
  
  if [ $PROOT_DOWNLOADED -eq 1 ]; then
    chmod 755 $ROOTFS_DIR/usr/local/bin/proot
    echo "PRoot installed successfully!"
  else
    echo "Warning: Could not download PRoot. Trying to use system proot if available..."
    if command -v proot >/dev/null 2>&1; then
      cp $(command -v proot) $ROOTFS_DIR/usr/local/bin/proot
      chmod 755 $ROOTFS_DIR/usr/local/bin/proot
    else
      echo "Error: PRoot not available. Installation failed."
      exit 1
    fi
  fi
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "Configuring system..."
  
  # Настройка DNS
  mkdir -p $ROOTFS_DIR/etc
  printf "nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1" > ${ROOTFS_DIR}/etc/resolv.conf
  
  # Создаем необходимые директории
  mkdir -p $ROOTFS_DIR/dev $ROOTFS_DIR/proc $ROOTFS_DIR/sys $ROOTFS_DIR/tmp
  chmod 1777 $ROOTFS_DIR/tmp
  
  # Базовая настройка
  echo "localhost" > $ROOTFS_DIR/etc/hostname
  echo "127.0.0.1 localhost" > $ROOTFS_DIR/etc/hosts
  
  touch $ROOTFS_DIR/.installed
  echo "System configuration completed!"
fi

# Очистка
rm -f /tmp/rootfs.tar.gz

CYAN='\e[0;36m'
WHITE='\e[0;37m'
GREEN='\e[0;32m'
RESET_COLOR='\e[0m'

display_gg() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${GREEN}✓ Ubuntu 20.04 LTS Installed Successfully!${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}Type 'exit' to leave the container${RESET_COLOR}"
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

clear
display_gg

echo "Starting Ubuntu container..."
echo ""

# Запускаем PRoot
$ROOTFS_DIR/usr/local/bin/proot \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w "/root" \
  -b /dev -b /sys -b /proc \
  -b /etc/resolv.conf \
  -b /etc/hosts \
  -b /etc/hostname \
  /bin/bash --login || \
  echo "If proot failed, try: ./usr/local/bin/proot -r . -0 -w /root /bin/bash"
