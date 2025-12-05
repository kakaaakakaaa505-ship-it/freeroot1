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
    warn "Скрипт запущен от root. Распаковка будет без ошибок."
    IS_ROOT=true
else
    info "Скрипт запущен без root прав. Некоторые файлы могут не распаковаться."
    IS_ROOT=false
fi

# Ссылки на Ubuntu rootfs (GitHub mirror)
UBUNTU_24_10_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-plucky-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_24_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-noble-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_22_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-jammy-aarch64-pd-v4.29.0.tar.xz"
UBUNTU_20_04_AARCH64="https://github.com/termux/proot-distro/releases/download/v4.29.0/ubuntu-focal-aarch64-pd-v4.29.0.tar.xz"

# Параметры по умолчанию
TARGET_DIR="$PWD/ubuntu-rootfs"
ROOTFS_FILE="ubuntu-rootfs.tar.xz"

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

# Распаковка rootfs с игнорированием ошибок для устройств
info "Распаковка rootfs..."
if command -v tar &> /dev/null; then
    # Показать содержимое архива
    info "Содержимое архива:"
    tar -tf "$ROOTFS_FILE" | head -5
    
    # Распаковка с игнорированием ошибок создания устройств
    if tar -xJf "$ROOTFS_FILE" --warning=no-unknown-keyword 2>/dev/null || tar -xJf "$ROOTFS_FILE" --no-same-owner 2>/dev/null; then
        info "Распаковка завершена!"
        
        # Удаление архива после распаковки
        rm -f "$ROOTFS_FILE"
        
        # Проверка содержимого
        if [ -d "./bin" ] && [ -d "./usr" ]; then
            info "Rootfs успешно распакован в: $TARGET_DIR"
            
            # Создание недостающих device файлов (если их нет)
            if [ ! -e "./dev/null" ]; then
                info "Создание базовых файлов устройств..."
                mkdir -p ./dev
                mknod ./dev/null c 1 3 2>/dev/null || true
                mknod ./dev/zero c 1 5 2>/dev/null || true
                mknod ./dev/random c 1 8 2>/dev/null || true
                mknod ./dev/urandom c 1 9 2>/dev/null || true
                mkdir -p ./dev/pts
                mkdir -p ./dev/shm
            fi
            
            # Создание минимальной структуры
            mkdir -p ./proc ./sys ./tmp ./run ./home
            chmod 1777 ./tmp
            
            info "Содержимое:"
            ls -la | head -10
        else
            # Проверяем, возможно архив содержит подпапку
            subdir=$(tar -tf "$ROOTFS_FILE" | head -1 | cut -d'/' -f1)
            if [ -d "$subdir" ]; then
                info "Обнаружена подпапка: $subdir"
                mv "$subdir"/* ./
                rm -rf "$subdir"
                info "Файлы перемещены в корень."
            else
                warn "Структура rootfs выглядит неполной. Проверяем..."
                ls -la
            fi
        fi
    else
        warn "Попытка альтернативного метода распаковки..."
        # Альтернативный метод
        xz -dc "$ROOTFS_FILE" | tar -x --exclude='./dev/*' 2>/dev/null
        if [ $? -eq 0 ]; then
            info "Распаковка завершена альтернативным методом!"
            rm -f "$ROOTFS_FILE"
        else
            error "Ошибка при распаковке архива."
            error "Попробуйте: tar -tf $ROOTFS_FILE | head -10"
            exit 1
        fi
    fi
else
    error "tar не найден. Установите tar и повторите попытку."
    exit 1
fi

# Создание базовых файлов
info "Настройка базовой системы..."
cat > "./etc/resolv.conf" 2>/dev/null << EOF || true
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > "./etc/hosts" 2>/dev/null << EOF || true
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
EOF

# Проверка наличия passwd и group файлов
if [ ! -f "./etc/passwd" ]; then
    warn "Файл /etc/passwd не найден. Создаем базовый..."
    echo "root:x:0:0:root:/root:/bin/bash" > ./etc/passwd
fi

if [ ! -f "./etc/group" ]; then
    warn "Файл /etc/group не найден. Создаем базовый..."
    echo "root:x:0:" > ./etc/group
fi

# Создание скрипта для входа в chroot
cd ..
cat > "start-ubuntu.sh" << 'EOF'
#!/bin/bash
echo "################################################################"
echo "#         Запуск Ubuntu в chroot/proot                         #"
echo "#   Используйте 'exit' для выхода                             #"
echo "################################################################"

TARGET_DIR="$(dirname "$(realpath "$0")")/ubuntu-rootfs"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Ошибка: Директория $TARGET_DIR не найдена!"
    exit 1
fi

echo "Директория: $TARGET_DIR"

# Проверка наличия proot (для работы без root)
if command -v proot &> /dev/null; then
    echo "Используется proot (без root прав)..."
    proot \
        -0 \
        -w /root \
        -r "$TARGET_DIR" \
        -b /dev \
        -b /proc \
        -b /sys \
        -b /dev/pts \
        -b /dev/shm \
        -b /tmp \
        /bin/bash --login
elif [ "$(id -u)" -eq 0 ]; then
    echo "Используется chroot (с root правами)..."
    mount --bind /dev "$TARGET_DIR/dev"
    mount --bind /proc "$TARGET_DIR/proc"
    mount --bind /sys "$TARGET_DIR/sys"
    mount --bind /dev/pts "$TARGET_DIR/dev/pts"
    chroot "$TARGET_DIR" /bin/bash
    umount "$TARGET_DIR/dev/pts"
    umount "$TARGET_DIR/sys"
    umount "$TARGET_DIR/proc"
    umount "$TARGET_DIR/dev"
else
    echo "Требуются root права или установите proot:"
    echo ""
    echo "Для Termux:"
    echo "    pkg install proot"
    echo ""
    echo "Для Debian/Ubuntu:"
    echo "    sudo apt install proot"
    echo ""
    echo "Для запуска с root правами:"
    echo "    sudo bash $0"
    echo ""
    echo "Или установите proot и запустите снова."
fi
EOF

chmod +x "start-ubuntu.sh"

# Финальное сообщение
echo ""
echo "#######################################################################################"
echo "#                            УСТАНОВКА ЗАВЕРШЕНА!"
echo "#######################################################################################"
echo ""
echo "Rootfs установлен в: $(realpath "$TARGET_DIR")"
echo ""
echo "Для запуска Ubuntu выполните:"
echo "    ./start-ubuntu.sh"
echo ""
echo "Если есть ошибки с устройствами, попробуйте:"
echo "    sudo ./start-ubuntu.sh"
echo ""
echo "Доступные команды внутри chroot:"
echo "    apt update && apt upgrade  # Обновление системы"
echo "    apt install <package>      # Установка пакетов"
echo ""
echo "#######################################################################################"
