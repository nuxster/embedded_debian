#!/bin/sh

# Индикация при выполнении процесса
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Проверка прав доступа
if [ $(id -u) -ne 0 ];then
	echo "Требуются права root"
	exit 1
fi

# Установка необходимого софта
if [ ! $(which debootstrap) ];then
        apt-get -y -q install debootstrap kpartx
fi

# Справка по параметрам запуска
if [ $# -lt 1 ]; then
	echo "Использование: $0 <размер образа в Mb>"
	exit 1
fi


#  
BUILD_CATALOG="/tmp/my_image/"
TARGET_CATALOG="$BUILD_CATALOG/mnt/"
IMG_NAME="hdd.img"
IMG_SIZE=$1
DEVICE=$BUILD_CATALOG$IMG_NAME
DISK="/dev/sda" 
LOOP_DEV="/dev/loop1"
LOOP_PART_1="p1"

# Debootstrap
ARCH_DBS="i386"
ARCH="486"
INCLUDE="vim,less,openssh-server,acpid,apt-utils"
EXTCLUDE="manpages,man-db,info,texinfo,rsyslog"
VARIANT="minbase"
RELEASE="stable"
MIRROR="http://ftp.psn.ru/debian/"

#
HOSTNAME="thesystem"

echo "Создание файла-образа $IMG_NAME"
echo "Заданный размер образа $IMG_SIZE Mb"

# Создание каталога для сборки
if [ ! -d "$BUILD_CATALOG" ]; then
	mkdir -p "$TARGET_CATALOG"
fi

# Создание файла-образа
if [ -e "$DEVICE" ]; then
	echo "Файл $DEVICE существует!\n"
	echo "Переименуйте или удалите его."
	exit 1
else
	dd if=/dev/urandom iflag=fullblock of="$DEVICE" bs=1M count="$IMG_SIZE" &
	spinner $!
fi

#losetup $LOOP_DEV $DEVICE

#Создание файловой системы
sed -e 's/\t\([\+0-9a-zA-Z]*\)[ \t].*/\1/' << EOF | fdisk $DEVICE
o 
n 
p
1


a
w
q

EOF

# Вывод информации о разделах
#fdisk -l $LOOP_DEV
kpartx -l $DEVICE
sleep 5

# Инициализация разделов
#partx -v -a $LOOP_DEV
kpartx -a $DEVICE
sleep 5

mkfs.ext4 -F -q /dev/mapper/loop0p1 || echo "Ошибка!\n Не могу создать файловую систему."
sleep 5
fsck.ext4 /dev/mapper/loop0p1

# Монтирование
mount -t ext4 /dev/mapper/loop0p1 $BUILD_CATALOG/mnt || echo "Ошибка!\n Не могу смонтировать устройство."

# Развертывание базовой системы
debootstrap --arch $ARCH_DBS --include $INCLUDE --exclude $EXCLUDE --variant=$VARIANT $RELEASE $TARGET_CATALOG $MIRROR

echo "Задание основных параметров системы ..."

# Монтирование
cat <<EOF > $TARGET_CATALOG/etc/fstab
#/dev/sda1 /boot               ext4    sync 		 0       2
/dev/sda1  /                   ext4    errors=remount-ro 0       1
EOF

# Параметры сети
echo $HOSTNAME > $TARGET_CATALOG/etc/hostname

cat <<EOF > $TARGET_CATALOG/etc/hosts
127.0.0.1       localhost
127.0.1.1       $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

cat <<EOF > $TARGET_CATALOG/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Настройки пакетного менеджера
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99no-translation

cat <<EOF >  /etc/apt/apt.conf
APT "";
APT::Install-Recommends "0";
APT::Install-Suggests "0";
APT::Immediate-Configure "0";
EOF

cat <<EOF > /etc/apt/sources.list
# Debian Stable Mirror
deb http://ftp.psn.ru/debian/ stable main contrib non-free

# Debian Security
deb http://security.debian.org/ stable/updates main contrib non-free

# stable-updates, previously known as 'volatile'
deb http://ftp.psn.ru/debian/ stable-updates main contrib non-free

# jessie-backports, previously on backports.debian.org
#deb http://ftp.psn.ru/debian/ jessie-backports main contrib non-free

# Debian Multimedia
# apt-get update && apt-get install deb-multimedia-keyring && apt-get update
#deb http://www.deb-multimedia.org stable main non-free
#deb http://www.deb-multimedia.org stable-backports main
EOF

#
mount --bind /dev/ $TARGET_CATALOG/dev
chroot $TARGET_CATALOG mount -t proc none /proc 
chroot $TARGET_CATALOG mount -t sysfs none /sys

LANG=C DEBIAN_FRONTEND=noninteractive chroot $TARGET_CATALOG apt-get install -y -q linux-image-$ARCH grub-legacy

#chroot $TARGET_CATALOG grub-install $DISK
#chroot $TARGET_CATALOG update-grub


mkdir -p $TARGET_CATALOG/boot/grub
cat > $TARGET_CATALOG/boot/grub/device.map <<EOF
(hd0)   /dev/loop0
EOF

#grub-install --no-floppy --root-directory=$TARGET_CATALOG /dev/loop0

grub-install --no-floppy --grub-mkdevicemap=$TARGET_CATALOG/boot/grub/device.map --root-directory=$TARGET_CATALOG /dev/loop0

chroot $TARGET_CATALOG grub-mkconfig -o /boot/grub/grub.cfg

#cat <<EOF > $TARGET_CATALOG/boot/grub/grub.cfg 
#set default="0"
#set timeout="3"
#
#menuentry "Debian" {
#    insmod gzio
#    insmod part_msdos
#    insmod ext2
#    linux (hd0,msdos1)/vmlinuz-3.16.0-4-586 root=/dev/sda1 rw console=tty0 console=ttyS0
#}
#EOF

echo "Укажите пароль пользователя root: "
while ! chroot $TARGET_CATALOG passwd root
do
	echo "Повторите еще раз"
done


chroot $TARGET_CATALOG umount /proc 
chroot $TARGET_CATALOG umount /sys
umount $TARGET_CATALOG/dev
umount $BUILD_CATALOG/mnt

kpartx -d $DEVICE

echo "ГОТОВО!\n"

exit 0


