---
layout: post
redirect_from: "posts/2008/08/26/howto-installing-grml-11-on-an-encrypted-usb-stick/"
title: "HOWTO: Installing grml 1.1 on an encrypted USB stick"
guid: "http://www.matthias-rampke.de/?p=94"
date: "2008-08-26 00:04:01"
author: "Matthias Rampke"
---
{% include JB/setup %}

<a href="http://grml.org/">grml</a> is a <a href="http://www.debian.org/">Debian</a> Sid based live Linux aimed at system recovery. It also offers installing to a hard disk while retaining the hardware autodetection. This is how to put a portable Linux on an encrypted USB drive.
<a href="http://grml.org/">grml</a> is a <a href="http://www.debian.org/">Debian</a> Sid based live Linux aimed at system recovery. It also offers installing to a hard disk while retaining the hardware autodetection. This is how to put a portable Linux on an encrypted USB drive.
<!--more-->
This walkthrough is based on <a href="http://testbit.eu/~timj/">Tim Janik</a>'s <a href="http://testbit.eu/~timj/blogstuff/DebianEncryption.txt">DebianEncryption</a>. Credit also goes to <a href="http://www.leere-signifikanten.net/">ml</a> for <a href="http://www.leere-signifikanten.net/2008/07/25/reset-desktop/">making me aware</a> of grml.

<h2>Prerequisites</h2>
You will need
<ul>
	<li>patience</li>
	<li>the <a href="http://grml.org/download/">grml 1.1 CD</a></li>
	<li>a 4GB USB Stick (larger is ok, hard disk will probably work as well). All data on it will be erased.</li>
	<li>at least 4 GB of hard disk space (on a unixishly formatted volume, i.e. FAT won't do)</li>
	<li>optional: additional hard disk space according to the size of the USB stick for intermediate backup
	</li><li>a computer capable of booting from USB (for testing). Note that my MacBook refused to boot a legacy OS (which a stock Debian is to a MacBook) from USB.</li>
	<li>a computer (may be virtual) capable of booting from the grml CD (the <strong>working system</strong>)</li>
</ul>
The latter two need not be identical. This process will work well within <a href="http://www.virtualbox.org/">VirtualBox</a> except for booting from USB, which is not supported.
<h2>Installing</h2>
Boot the working system. Plug in the USB stick. In <code>/dev</code> a few <code>usb-sd*</code>-devices will emerge after a few seconds. I will assume this is <code>usb-sda</code> (and possibly <code>usb-sdaN</code>). Run <code>cfdisk /dev/usb-sda</code>. Delete all partitions. Create one <del datetime="2008-08-27T14:15:05+00:00">50</del> 100 MB partition and one using the remaining space. Write to disk and quit.

Run <code>grml2hd</code>. In the Partitions dialog select the larger of the just created partitions. The device may be named <code>sda</code>, this is ok; just be careful not to trash your hard disk. In the next dialog, install the bootloader to MBR. Be careful: select <code>mbr</code>, then press the <code>SPACE</code> key, and only then press <code>ENTER</code>. Choose a filesystem of your liking, <code>ext3</code> is fine. Start the installation and go get some coffee.

Now it's time to answer some more questions. No change for the bootparameters. Choose a name for your system Select your keyboard and language settings - these will be the defaults on boot, but you can always invoke <code>grml-quickconfig</code> to change the keyboard setting temporarily. Enter root and user password. Continue with the default options, but choose Grub as boot manager.

Create a file system on the 100 MB partition, mount both and move the <code>/boot</code> directory:
<pre><code>mkfs.ext3 /dev/usb-sda1
mount /dev/usb-sda1 /mnt/usb-sda1 -t ext3
mount /dev/usb-sda2 /mnt/usb-sda2 -t ext3
cp -ax /mnt/usb-sda2/boot/. /mnt/usb-sda1/.
rm -R /mnt/usb-sda2/boot/*
</code></pre>

Get the volume id of your boot partition: <code>vol_id --uuid /dev/usb-sda1</code>. Now edit <code>/mnt/usb-sda2/etc/fstab</code> and insert right after the first line (this is one line):

<code>/dev/disk/by-uuid/&lt;volume id of your boot partition&gt; /boot ext3 errors=remount-ro 0 1</code>

Edit <code>/mnt/usb-sda1/grub/menu.lst</code>: change the line <pre><code># groot=(hd?,1)</code></pre> (where <code>?</code> is any number) to <pre><code># groot=(hd0,0)</code></pre>

Now <code>chroot</code> into the usb system, mount some filesystems and update Grub:
<pre><code>mount --bind /dev /mnt/usb-sda2/dev
chroot /mnt/usb-sda2
mount /dev/usb-sda1 /boot -t ext3
mount /sys && mount /proc
echo "(hd0) /dev/sda" > /boot/grub/device.map
update-grub && grub-install /dev/usb-sda
</code></pre>

You should now be able to boot from your USB system.

<h2>Encrypting</h2>

Boot into the working system again and plug in the USB stick. It may be advisable to do a complete backup of your progress so far; to do that mount your hard disk (<code>mount /mnt/&lt;your HD&gt;</code>) and run
<pre><code>dd if=/dev/usb-sda of=/mnt/&lt;your HD&gt;/&lt;somewhere safe&gt; bs=1M</code></pre>


Copy the contents of your root partition to your HD:
<pre><code>mount /dev/usb-sda2 /mnt/usb-sda2 -t ext3
cp -ax /mnt/usb-sda2/ /mnt/&lt;your HD&gt;/&lt;somwhere safe&gt;/
umount /mnt/usb-sda2
</code></pre>

Now overwrite the root partition with random data, so unused sectors can not be distinguished:
<pre><code>dd if=/dev/urandom of=/dev/usb-sda2 bs=1M</code></pre>

Take a walk. Now it's time to setup the encrypted device and copy the system files back:
<pre><code>echo "root /dev/usb-sda2 none luks" &gt;&gt; /etc/crypttab
cryptsetup luksFormat /dev/usb-sda2
/etc/init.d/cryptdisks start
mkfs.ext3 /dev/mapper/root
mkdir /mnt/root
mount /dev/mapper/root /mnt/root -t ext3
cp -ax /mnt/&lt;your HD&gt;/&lt;somwhere safe&gt;/. /mnt/root/.</code></pre>

It is advisable to choose a passphrase which can be easily typed on most keyboard layouts, i.e. which consists only of numbers and letters, and no y or z. You will have to type it at system boot, before any keymap is loaded.

<code>chroot</code> into the USB system:
<pre><code>mount --bind /dev /mnt/root/dev
chroot /mnt
rm -f /etc/mtab && touch /etc/mtab
mount -o remount /
mount /proc && mount /sys && mount /boot</code></pre>

Edit <code>/etc/fstab</code>: change the root line (where the second column is just <code>/</code>) to <pre><code>/dev/mapper/root / ext3 errors=remount-ro 0 1</code></pre>

Edit <code>/boot/grub/menu.lst</code>: change the <code># kopt=</code> line to
<pre><code># kopt=root=/dev/mapper/root rootdelay=15 ro</code></pre>

Note the output of <code>vol_id --uuid /dev/usb-sda2</code> and edit <code>/etc/crypttab</code>:  Insert the line
<pre><code>root /dev/disk/by-uuid/&lt;output of vol_id&gt; none luks</code></pre>

Run <code>update-initramfs -u && update-grub</code>. This is it, your USB system is ready to boot.

