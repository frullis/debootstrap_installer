#!/bin/sh

#setup your network and fix resolver first

sgdisk -n 1:0:+64M -t 1:ef02 -n2:0:+500M -n3:0:0 -p /dev/sda
mkfs.ext4 /dev/sda2

#encrypt and set a password
cryptsetup -s 512 -c aes-xts-plain64 luksFormat /dev/sda3
cryptsetup luksOpen /dev/sda3 sda3_crypt

#This may give you some error about cannot connect to lvmetad, (But should work anyway)
pvcreate /dev/mapper/sda3_crypt
vgcreate vg0 /dev/mapper/sda3_crypt

lvcreate -L 8GB -n sys-root vg0
lvcreate -L 4GB -n sys-var vg0
lvcreate -L 4GB -n sys-home vg0
lvcreate -L 2GB -n sys-tmp vg0
lvcreate -L 4GB -n sys-swap vg0

for i in home root tmp var; do mkfs.ext4 -L $i /dev/mapper/vg0-sys--$i; done
mkswap /dev/mapper/vg0-sys--swap
mount /dev/mapper/vg0-sys--root /mnt

for i in boot home tmp var; do mkdir /mnt/$i; done
mount /dev/sda2 /mnt/boot

for i in home tmp var; do mount /dev/mapper/vg0-sys--$i /mnt/$i; done
swapon /dev/mapper/vg0-sys--swap
chmod 1777 /mnt/tmp

debootstrap --arch amd64 buster /mnt/ http://ftp.se.debian.org/debian

mount -o bind /dev /mnt/dev
mount -o bind /dev/pts /mnt/dev/pts
mount -o bind /proc /mnt/proc
mount -o bind /sys /mnt/sys
mount -o bind /run /mnt/run

#chroot /mnt /bin/bash
chroot /mnt passwd root
chroot /mnt cp /proc/mounts /etc/mtab

export HOSTNAME=stoth2
export IP=98.128.186.83
export DOMAINNAME=example.net

echo "$HOSTNAME" > /mnt/etc/hostname
echo "$HOSTNAME" > /mnt/etc/mailname
echo "$IP $HOSTNAME ${HOSTNAME}.${DOMAINNAME}" >> /mnt/etc/hosts

cat > /mnt/etc/resolv.conf << EOF
search $DOMAINNAME
nameserver 1.1.1.1
EOF

cat > /mnt/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eno1
iface eno1 inet static
	address ${IP}
	netmask 255.255.255.0
	broadcast 10.64.6.255
	gateway 10.64.6.1
	pre-up /sbin/ip addr flush dev eno1 || true
EOF

cat > /mnt/etc/apt/sources.list << EOF
deb http://ftp.se.debian.org/debian/ buster main non-free contrib
deb-src http://ftp.se.debian.org/debian/ buster main non-free contrib
deb http://security.debian.org/ buster/updates main non-free contrib
deb-src http://security.debian.org/ buster/updates main non-free contrib
deb http://ftp.se.debian.org/debian/ buster-updates main non-free contrib
deb-src http://ftp.se.debian.org/debian/ buster-updates main non-free contrib
EOF

chroot /mnt apt-get update
chroot /mnt apt upgrade -y vim linux-base linux-image-amd64 linux-headers-amd64 grub-pc cryptsetup lvm2 initramfs-tools openssh-server busybox dropbear locales firmware-bnx2
chroot /mnt dpkg-reconfigure locales

echo "sda3_crypt UUID=$(blkid -s UUID -o value /dev/sda3) none luks" > /mnt/etc/crypttab

cat > /mnt/etc/fstab << EOF
proc                        /proc   proc    defaults    0 0
devpts          /dev/pts        devpts  rw,noexec,nosuid,gid=5,mode=620 0  0
UUID=$(blkid -s UUID -o value /dev/sda2)                    /boot   ext4    defaults   0 0
UUID=$(blkid -s UUID -o value /dev/mapper/vg0-sys--root) /       ext4    defaults   0 1
UUID=$(blkid -s UUID -o value /dev/mapper/vg0-sys--var)  /var    ext4    defaults   0 2
UUID=$(blkid -s UUID -o value /dev/mapper/vg0-sys--home) /home   ext4    rw,nosuid,noexec,nodev   0 2
UUID=$(blkid -s UUID -o value /dev/mapper/vg0-sys--tmp) /tmp   ext4    rw,nosuid,noexec,nodev   0 2
UUID=$(blkid -s UUID -o value /dev/mapper/vg0-sys--swap)  none    swap defaults     0 0
EOF

chroot /mnt ln -sf /proc/mounts /etc/mtab

mkdir -p /mnt/root/.ssh
chmod 600 /mnt/root/.ssh

echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDss65zE2i1JDVdm9ybW1rXf7IeBHBgBzXKulA7L8iT9Rhzr/3U9F+GQCudmSx0GGGr9+N/FAVkZGajOxshPpd6y6+j4GARg5IYG33W+U/9jjrwKXHHNCs6ZGY/AXoNEcVHRUqr8D0BxpruvZVUYIz3oWG2RHYhBnjIg8sIH1+HjY8zhtkcfzrmo1coahK73xnrg4V9Jw9fRpRj9vqD57nuIyypbvY3cgGoiCJXSzXUme1+tT8dSIfW8Iufcv0ppc8e18x7LYjXP1uwJgKLItYZYwUWD//KbT0n3dHUscvarsE8BTwZVedxC2ilX2s8zSm9e7nhuU4XcQnVcrtrNLpz krullis@krullis-UX330CAK" > /mnt/root/.ssh/authorized_keys

#Enable dropbear
sed -i "s/NO_START=1/NO_START=0/" /mnt/etc/default/dropbear
echo "DEVICE=eno1" >> /mnt/etc/initramfs-tools/initramfs.conf
sed -i "s/^#CRYPTSETUP=$/CRYPTSETUP=y/" /mnt/etc/cryptsetup-initramfs/conf-hook

echo "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=\"/bin/cryptroot-unlock\" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDss65zE2i1JDVdm9ybW1rXf7IeBHBgBzXKulA7L8iT9Rhzr/3U9F+GQCudmSx0GGGr9+N/FAVkZGajOxshPpd6y6+j4GARg5IYG33W+U/9jjrwKXHHNCs6ZGY/AXoNEcVHRUqr8D0BxpruvZVUYIz3oWG2RHYhBnjIg8sIH1+HjY8zhtkcfzrmo1coahK73xnrg4V9Jw9fRpRj9vqD57nuIyypbvY3cgGoiCJXSzXUme1+tT8dSIfW8Iufcv0ppc8e18x7LYjXP1uwJgKLItYZYwUWD//KbT0n3dHUscvarsE8BTwZVedxC2ilX2s8zSm9e7nhuU4XcQnVcrtrNLpz krullis@krullis-UX330CAK" > /mnt/etc/dropbear-initramfs/authorized_keys
#export IP=${IP}::98.128.186.83:255.255.255.192:${HOSTNAME}:enp3s0f0

cat > /mnt/etc/initramfs-tools/conf.d/network_config << EOF
export IP=${IP}::10.64.6.65:255.255.255.0:${HOSTNAME}:eno1
EOF

echo "bnx2" >> /mnt/etc/initramfs-tools/modules

chroot /mnt update-initramfs -u -k all
chroot /mnt update-grub

exit
umount /mnt/{boot,var,home}
sync
swapoff -L swap
