cat > start-ubuntu.sh << 'EOF'
#!/bin/bash
echo "################################################################"
echo "#         Запуск Ubuntu 24.10 в chroot/proot                   #"
echo "#   Используйте 'exit' для выхода                             #"
echo "################################################################"

TARGET_DIR="$(dirname "$(realpath "$0")")/ubuntu-rootfs"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Ошибка: Директория $TARGET_DIR не найдена!"
    exit 1
fi

echo "Директория: $TARGET_DIR"

# Проверка наличия proot
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
    echo "Требуются root права или установите proot!"
    echo ""
    echo "Для запуска с proot (установите если нет):"
    echo "    apt install proot  # или pkg install proot в Termux"
    echo ""
    echo "Для запуска с root правами:"
    echo "    sudo bash $0"
fi
EOF

chmod +x start-ubuntu.sh
