#!/bin/bash

BROOT=${BROOT-/mnt/gentoo}
SCRIPTSDIR=$(cd $(dirname $0); cd ../; pwd)
GENTOO_MIRROR=$(bash ${SCRIPTSDIR}/scripts/bootstrap-misc-mirror.sh)

cd /root

# Use swap partition as a temporary storage
swapoff /dev/vda2
fdisk /dev/vda <<EOF
t
2
83
w
EOF
mkfs.ext3 /dev/vda2
mkdir -p ${BROOT}
mount /dev/vda2 ${BROOT}

# Mount and Copy contents included in the latest minimal-install iso image
rm -f /root/install-*.iso
wget $(wget -q -O - ${GENTOO_MIRROR}/releases/amd64/autobuilds/current-iso/ | \
	egrep -o "(https?|ftp)://[^\"]+\.iso" | head -n 1)
mkdir -p /mnt/cdrom
mount -o loop /root/install-*.iso /mnt/cdrom
cp -a /mnt/cdrom/* ${BROOT}

# Install virtio modules into initrd
yum -y install squashfs-tools
unsquashfs image.squashfs
D=${BROOT}/squashfs-root

mkdir -p ${BROOT}/initrd
cd ${BROOT}/initrd
zcat ../isolinux/gentoo.igz | cpio -i
cp ${D}/lib/modules/*-gentoo*/kernel/drivers/block/virtio_blk.ko ./lib/modules/*-gentoo*/kernel/drivers/block/
cp -r ${D}/lib/modules/*-gentoo*/kernel/drivers/virtio ./lib/modules/*-gentoo*/kernel/drivers/
find . | sort | cpio -H newc -o | gzip > ../isolinux/gentoo.igz
cd ${BROOT}
rm -rf ${BROOT}/initrd
umount /mnt/cdrom
rm -f /root/install-*.iso

# Backup network configuration
mkdir -p ${D}/root/netconfig
ifconfig eth0 | egrep -o "inet addr:[0-9.]+" | egrep -o "[0-9.]+" > ${D}/root/netconfig/addr.txt
ifconfig eth0 | egrep -o "Bcast:[0-9.]+" | egrep -o "[0-9.]+" > ${D}/root/netconfig/bcast.txt
ifconfig eth0 | egrep -o "Mask:[0-9.]+" | egrep -o "[0-9.]+" > ${D}/root/netconfig/mask.txt
route | egrep -o "default +[0-9.]+" | egrep -o "[0-9.]+" > ${D}/root/netconfig/gw.txt
cat /etc/resolv.conf | egrep -o 'nameserver +[0-9.]+' | egrep -o '[0-9.]+' | \
	perl -pe 's/\n/ /g' > ${D}/root/netconfig/resolv.txt

# Create a new squashfs image
cp -r ${SCRIPTSDIR} ${D}/root/gentoo-sakura-vps
mksquashfs squashfs-root image.squashfs
rm -rf ${D}

# Grub configuration
sed -i -e "s:^hiddenmenu::" /boot/grub/grub.conf

cat >> /boot/grub/grub.conf <<EOM

title Gentoo install
	root (hd0,1)
	kernel /isolinux/gentoo root=/dev/ram0 init=/linuxrc looptype=squashfs loop=/image.squashfs cdroot=/dev/vda2 initrd=gentoo.igz udev nodevfs console=tty0 console=ttyS0,115200n8r doload=virtio,virtio_ring,virtio_pci,virtio_blk
	initrd /isolinux/gentoo.igz
EOM

#reboot
