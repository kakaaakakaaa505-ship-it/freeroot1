#!/bin/bash
#
# Foxytoux INSTALLER - Исправленная версия
# Использует GitHub mirror для обхода блокировок
#

set -e

echo "#######################################################################################"
echo "#"
echo "#                             Foxytoux INSTALLER (Fixed)"
echo "#"
echo "#                     Исправлено для работы с GitHub mirror"
echo "#"
echo "#######################################################################################"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для вывода
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка root прав
if [ "$EUID" -eq 0 ]; then 
    error "Не запускайте скрипт от root!"
    exit 1
fi

# Ссылки на Ubuntu rootfs (GitHub mirror)
UBUNTU_24_10_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-plucky-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_24_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-noble-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_22_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-jammy-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_20_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-focal-aarch64-pd-v4.29.0.tar.xz"

# Параметры по умолчанию
TARGET_DIR="$PWD/ubuntu-rootfs"
ROOTFS_FILE="ubuntu-rootfs.tar.xz"
USE_UBUNTU_24_10=true

# Выбор версии Ubuntu
echo "Выберите версию Ubuntu:"
echo "1) Ubuntu 24.10 (Plucky) [Рекомендуется]"
echo "2) Ubuntu 24.04 (Noble)"
echo "3) Ubuntu 22.04 (Jammy)"
echo "4) Ubuntu 20.04 (Focal)"
read -p "Ваш выбор (1-4): " ubuntu_choice

case $ubuntu_choice in
    1)
        ROOTFS_URL="$UBUNTU_24_10_AARCH64"
        UBUNTU_VERSION="24.10"
        ;;
    2)
        ROOTFS_URL="$UBUNTU_24_04_AARCH64"
        UBUNTU_VERSION="24.04"
        ;;
    3)
        ROOTFS_URL="$UBUNTU_22_04_AARCH64"
        UBUNTU_VERSION="22.04"
        ;;
    4)
        ROOTFS_URL="$UBUNTU_20_04_AARCH64"
        UBUNTU_VERSION="20.04"
        ;;
    *)
        info "Используется Ubuntu 24.10 (по умолчанию)"
        ROOTFS_URL="$UBUNTU_24_10_AARCH64"
        UBUNTU_VERSION="24.10"
        ;;
esac

info "Установка Ubuntu $UBUNTU_VERSION для ARM64 (aarch64)..."

# Создание целевой директории
if [ -d "$TARGET_DIR" ]; then
    warn "Директория $TARGET_DIR уже существует."
    read -p "Удалить и продолжить? (y/N): " confirm
    if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
        rm -rf "$TARGET_DIR"
        info "Директория удалена."
    else
        error "Установка отменена."
        exit 1
    fi
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Проверка наличия wget
if ! command -v wget &> /dev/null; then
    error "wget не найден. Установите wget и повторите попытку."
    exit 1
fi

# Скачивание rootfs
info "Скачивание Ubuntu rootfs с GitHub..."
info "URL: $ROOTFS_URL"

if wget --timeout=30 --tries=3 --show-progress -O "$ROOTFS_FILE" "$ROOTFS_URL"; then
    info "Скачивание завершено успешно!"
    
    # Проверка размера файла
    file_size=$(stat -c%s "$ROOTFS_FILE" 2>/dev/null || stat -f%z "$ROOTFS_FILE")
    if [ "$file_size" -lt 1000000 ]; then
        error "Файл слишком маленький ($file_size байт). Возможно, скачивание не удалось."
        exit 1
    fi
    
    info "Размер файла: $((file_size / 1024 / 1024)) MB"
else
    error "Не удалось скачать rootfs."
    error "Возможные причины:"
    error "1. Нет интернет-соединения"
    error "2. GitHub заблокирован в вашей сети"
    error "3. Файл был удален из репозитория"
    exit 1
fi

# Распаковка rootfs
info "Распаковка rootfs..."
if command -v tar &> /dev/null; then
    if tar -xJf "$ROOTFS_FILE" --checkpoint=.100; then
        info "Распаковка завершена!"
        
        # Удаление архива после распаковки
        rm -f "$ROOTFS_FILE"
        
        # Проверка содержимого
        if [ -d "./etc" ] && [ -d "./bin" ] && [ -d "./usr" ]; then
            info "Rootfs успешно распакован в: $TARGET_DIR"
            info "Содержимое:"
            ls -la | head -10
        else
            warn "Структура rootfs выглядит неполной. Возможны проблемы."
        fi
    else
        error "Ошибка при распаковке архива."
        error "Проверьте целостность файла: tar -tf $ROOTFS_FILE | head -5"
        exit 1
    fi
else
    error "tar не найден. Установите tar и повторите попытку."
    exit 1
fi

# Создание базовых файлов
info "Настройка базовой системы..."
cat > "$TARGET_DIR/etc/resolv.conf" << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > "$TARGET_DIR/etc/hosts" << EOF
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
EOF

# Создание скрипта для входа в chroot
cat > "$TARGET_DIR/../start-ubuntu.sh" << EOF
#!/bin/bash
echo "Запуск Ubuntu $UBUNTU_VERSION в chroot..."
echo "Используйте 'exit' для выхода"

# Проверка наличия proot (для работы без root)
if command -v proot &> /dev/null; then
    proot -0 -w /root -r "$TARGET_DIR" -b /dev -b /proc -b /sys /bin/bash
elif [ "\$(id -u)" -eq 0 ]; then
    chroot "$TARGET_DIR" /bin/bash
else
    echo "Требуются root права или установите proot:"
    echo "Для Debian/Ubuntu: apt install proot"
    echo "Для Termux: pkg install proot"
    echo "Запуск с sudo: sudo chroot \"$TARGET_DIR\" /bin/bash"
fi
EOF

chmod +x "$TARGET_DIR/../start-ubuntu.sh"

# Финальное сообщение
echo ""
echo "#######################################################################################"
echo "#                            УСТАНОВКА ЗАВЕРШЕНА!"
echo "#######################################################################################"
echo ""
echo "Rootfs установлен в: $(realpath "$TARGET_DIR")"
echo ""
echo "Для запуска Ubuntu выполните:"
echo "    cd $(dirname "$(realpath "$TARGET_DIR")")"
echo "    ./start-ubuntu.sh"
echo ""
echo "Или с root правами:"
echo "    sudo chroot \"$TARGET_DIR\" /bin/bash"
echo ""
echo "Доступные команды внутри chroot:"
echo "    apt update && apt upgrade  # Обновление системы"
echo "    apt install <package>      # Установка пакетов"
echo "    apt-get clean              # Очистка кэша"
echo ""
echo "#######################################################################################"
