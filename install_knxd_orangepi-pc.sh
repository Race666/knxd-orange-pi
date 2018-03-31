#!/bin/bash
set -e
# Exit on error
###############################################################################
# Script to compile and install knxd on a debian jessie (8) based systems
# 
# Michael Albert info@michlstechblog.info
# 20.09.2017
# Changes
# Version: 0.1.0 (Draft Version)
# This is the first release of the try to install knxd on Orange Pi PC.
# This script is adopted from the install_knxd_systemd.sh script
#
# v0.2.0   02.11.2017  Michael     Enable UART3 for connecting a TPUART module
# v0.3.0   30.03.2018  Michael     EMI Timeout Patch 
#                                  systemd service type simple => forking
#                                  set low latency on serial devices
# v0.3.1   30.03.2018  Michael     Checkout knxd master 
#
# Open issues:
# 
#
###############################################################################
if [ "$(id -u)" != "0" ]; then
   echo "     Attention!!!"
   echo "     Start script must run as root" 1>&2
   echo "     Start a root shell with"
   echo "     sudo su -"
   exit 1
fi
# define environment
export BUILD_PATH=$HOME/knxdbuild
export INSTALL_PREFIX=/usr/local
export EIB_ADDRESS_KNXD="1.1.128"
export EIB_START_ADDRESS_CLIENTS_KNXD="1.1.129"
export EIB_NUMBER_OF_CLIENT_KNX_CLIENT_ADDRESSES=8


# Requiered packages
apt-get update 
apt-get -y upgrade
apt-get -y install build-essential cmake
apt-get -y install automake autoconf libtool 
apt-get -y install git 
apt-get -y install debhelper cdbs 
apt-get -y install libsystemd-dev libsystemd0 pkg-config libusb-dev libusb-1.0-0-dev
apt-get -y install libev-dev 
apt-get -y install nmap crudini

# New User knxd 
# For accessing serial devices => User knxd dialout group
set +e
getent passwd knxd
if [ $? -ne 0 ]; then
	useradd knxd -s /bin/false -U -M -G dialout
fi	
set -e

# On Raspberry add user pi to group knxd
set +e
getent passwd pi
if [ $? -eq 0 ]; then
	usermod -a -G knxd pi
fi	
set -e

# And knxd himself to group knxd too
usermod -a -G knxd knxd

# Add /usr/local library to libpath
export LD_LIBRARY_PATH=$INSTALL_PREFIX/lib:$LD_LIBRARY_PATH
if [ ! -d "$BUILD_PATH" ]; then mkdir -p "$BUILD_PATH"; fi
cd $BUILD_PATH

if [ -d "$BUILD_PATH/fmt" ]; then
	echo "libfmt repository found"
	cd "$BUILD_PATH/fmt"
	# git pull
else
	git clone https://github.com/fmtlib/fmt.git fmt
	cd fmt
fi
# v3.0.1 libfmt has some compile errors => fallback to 3.0.0
git checkout tags/3.0.0
cmake -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX fmt/
make all
cp libfmt.a $INSTALL_PREFIX/lib

cd $BUILD_PATH
if [ -d "$BUILD_PATH/knxd" ]; then
	echo "knxd repository found"
	cd "$BUILD_PATH/knxd"
	git pull
else
	git clone https://github.com/knxd/knxd knxd
	cd knxd
fi

git checkout stable

if [ "$APPLY_EMI_TIMEOUT_PATCH" == "y" ]; then
cat > $BUILD_PATH/patch.emi_timeout <<EOF
--- src/libserver/emi_common.cpp        2017-10-10 21:39:21.760000000 +0200
+++ src/libserver/emi_common.cpp        2017-10-10 21:40:13.448000000 +0200
@@ -60,8 +60,11 @@
     return false;
   if(!LowLevelFilter::setup())
     return false;
-  send_timeout = cfg->value("send-timeout",300) / 1000.;
-  max_retries = cfg->value("send-retries",3);
+  // send_timeout = cfg->value("send-timeout",300) / 1000.;
+  // max_retries = cfg->value("send-retries",3);
+  send_timeout = cfg->value("send-timeout",6000) / 1000.;
+  max_retries = cfg->value("send-retries",5);
+
   monitor = cfg->value("monitor",false);

   return true;
--- tools/version.sh    2017-10-11 09:38:35.448000000 +0200
+++ tools/version.sh    2017-10-11 09:51:55.516000000 +0200
@@ -5,4 +5,5 @@
 lgit=\$(git rev-parse --short \$(git rev-list -1 HEAD debian/changelog) )
 if test "\$git" != "\$lgit" ; then
        echo -n ":\$git"
+       echo -n "-emipatch"
 fi
EOF
patch -p0 --ignore-whitespace -i $BUILD_PATH/patch.emi_timeout
fi


#git checkout master
# All previously installed libraries have to be removed
set +e
rm $INSTALL_PREFIX/lib/libeibclient* > /dev/null 2>&1
set -e

bash bootstrap.sh

./configure \
    --enable-tpuart \
    --enable-ft12 \
	--enable-dummy \
    --enable-eibnetip \
    --enable-eibnetserver \
	--disable-systemd \
	--enable-busmonitor \
    --enable-eibnetiptunnel \
    --enable-eibnetipserver \
    --enable-groupcache \
    --enable-usb \
    --prefix=$INSTALL_PREFIX \
	CPPFLAGS="-I$BUILD_PATH/fmt"
# For USB Debugging add -DENABLE_LOGGING=1 and -DENABLE_DEBUG_LOGGING=1 to CFLAGS and CPPFLAGS:
# 	CFLAGS="-static -static-libgcc -static-libstdc++ -DENABLE_LOGGING=1 -DENABLE_DEBUG_LOGGING=1" \
#	CPPFLAGS="-static -static-libgcc -static-libstdc++ -DENABLE_LOGGING=1 -DENABLE_DEBUG_LOGGING=1" 
make clean && make && make install

# http://knx-user-forum.de/342820-post9.html
cat > /etc/udev/rules.d/90-knxusb-devices.rules <<EOF
# Siemens KNX
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0111", ACTION=="add", GROUP="knxd", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0112", ACTION=="add", GROUP="knxd", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="0681", ATTR{idProduct}=="0014", ACTION=="add", GROUP="knxd", MODE="0664"
# Merlin Gerin KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0141", ACTION=="add", GROUP="knxd", MODE="0664"
# Hensel KNX-USB Interface 
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0121", ACTION=="add", GROUP="knxd", MODE="0664"
# Busch-Jaeger KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="145c", ATTR{idProduct}=="1330", ACTION=="add", GROUP="knxd", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="145c", ATTR{idProduct}=="1490", ACTION=="add", GROUP="knxd", MODE="0664"
# ABB STOTZ-KONTAKT KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="147b", ATTR{idProduct}=="5120", ACTION=="add", GROUP="knxd", MODE="0664"
# Feller KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0026", ACTION=="add", GROUP="knxd", MODE="0664"
# JUNG KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0023", ACTION=="add", GROUP="knxd", MODE="0664"
# Gira KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0022", ACTION=="add", GROUP="knxd", MODE="0664"
# Berker KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0021", ACTION=="add", GROUP="knxd", MODE="0664"
# Insta KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0020", ACTION=="add", GROUP="knxd", MODE="0664"
# Weinzierl KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0104", ACTION=="add", GROUP="knxd", MODE="0664"
# Weinzierl KNX-USB Interface (RS232)
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0103", ACTION=="add", GROUP="knxd", MODE="0664"
# Weinzierl KNX-USB Interface (Flush mounted)
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0102", ACTION=="add", GROUP="knxd", MODE="0664"
# Tapko USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0490", ACTION=="add", GROUP="knxd", MODE="0664"
# Hager KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0025", ACTION=="add", GROUP="knxd", MODE="0664"
# preussen automation USB2KNX
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0492", ACTION=="add", GROUP="knxd", MODE="0664"
# Merten KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0024", ACTION=="add", GROUP="knxd", MODE="0664"
# b+b EIBWeiche USB
SUBSYSTEM=="usb", ATTR{idVendor}=="04cc", ATTR{idProduct}=="0301", ACTION=="add", GROUP="knxd", MODE="0664"
# MDT KNX_USB_Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0491", ACTION=="add", GROUP="knxd", MODE="0664"
# Siemens 148/12 KNX Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0908", ATTR{idProduct}=="02dd", ACTION=="add", GROUP="knxd", MODE="0664"
# Low Latency for  Busware TUL TPUART USB
ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="204b", KERNELS=="1-4", SYMLINK+="ttyTPUART", RUN+="/bin/setserial /dev/%k low_latency", GROUP="dialout", MODE="0664"
# Test rules example:
# udevadm info --query=all --attribute-walk --name=/dev/ttyS0
# udevadm test /dev/ttyS0 
# ACTION=="add",SUBSYSTEM=="tty", ATTR{port}=="0x3F8",SYMLINK+="ttyTPUART%n",RUN+="/bin/setserial /dev/%k low_latency", GROUP="dialout", MODE="0664"
EOF


cat > /etc/default/knxd <<EOF
# Command line parameters for knxd. TPUART Backend
# Serial device Raspberry
# KNXD_OPTIONS="--eibaddr=$EIB_ADDRESS_KNXD --client-addrs=$EIB_START_ADDRESS_CLIENTS_KNXD:$EIB_NUMBER_OF_CLIENT_KNX_CLIENT_ADDRESSES -d -D -T -R -S -i --listen-local=/tmp/knx -b tpuarts:/dev/ttyAMA0"
# Serial device Orange PC TPUART Backend
KNXD_OPTIONS="--eibaddr=$EIB_ADDRESS_KNXD --client-addrs=$EIB_START_ADDRESS_CLIENTS_KNXD:$EIB_NUMBER_OF_CLIENT_KNX_CLIENT_ADDRESSES -d -D -T -R -S -i --listen-local=/tmp/knx -b tpuarts:/dev/ttyS3"
# Tunnel Backend
# KNXD_OPTIONS="--eibaddr=$EIB_ADDRESS_KNXD --client-addrs=$EIB_START_ADDRESS_CLIENTS_KNXD:$EIB_NUMBER_OF_CLIENT_KNX_CLIENT_ADDRESSES -d -D -T -R -S -i --listen-local=/tmp/knx -b ipt:192.168.56.1"
# USB Backend
# KNXD_OPTIONS="--eibaddr=$EIB_ADDRESS_KNXD --client-addrs=$EIB_START_ADDRESS_CLIENTS_KNXD:$EIB_NUMBER_OF_CLIENT_KNX_CLIENT_ADDRESSES -d -D -T -R -S -i --listen-local=/tmp/knx -b usb:"
EOF

chown knxd:knxd /etc/default/knxd
chmod 644 /etc/default/knxd

# Systemd knxd unit
cat >  /lib/systemd/system/knxd.service <<EOF
[Unit]
Description=KNX Daemon
After=network.target

[Service]
EnvironmentFile=/etc/default/knxd
ExecStart=/usr/local/bin/knxd -p /run/knxd/knxd.pid \$KNXD_OPTIONS
Type=forking
PIDFile=/run/knxd/knxd.pid
User=knxd
Group=knxd

[Install]
WantedBy=multi-user.target network-online.target
EOF

# Create knxd folder under /run
cat > /etc/tmpfiles.d/knxd.conf <<EOF
D    /run/knxd 0744 knxd knxd
EOF

# Library Path
cat > /etc/ld.so.conf.d/knxd.conf <<EOF
/usr/local/lib
EOF

ldconfig


# Enable at Startup
systemctl enable knxd.service
sync


# Disable serial console => Not necessary. UART3 is used
# sed -e's/console=.*/console=display/g' /boot/armbianEnv.txt --in-place=.bak
# systemctl disable serial-getty@ttyS0.service > /dev/null 2>&1

# Enable UART3 for connecting a TPUART module
bin2fex /boot/script.bin /tmp/script.fex
crudini --set /tmp/script.fex uart3 uart_used 1
fex2bin /tmp/script.fex /boot/script.bin


echo "Please reboot your device!"
