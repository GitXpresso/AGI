#!/bin/bash
GUACAMOLE_VERSION="1.5.5"
if [ -d /etc/dnf ]; then
packages=("wget" "cairo-devel" "libjpeg-devel" "libpng-devel" "uuid-devel" "freerdp-devel" "pango-devel" "libssh2-devel" "libtelnet-devel" "libvncserver-devel" "pulseaudio-libs-devel" "openssl-devel" "libvorbis-devel" "libwebsockets-devel" "tomcat-native" "tomcat")
for dnfpackages in "$(packages[@])'; do
     sudo dnf list installed | grep "$packages[@]" > /dev/null 2>&1
     if [ $? -ne 0 ]; then
         export installed="No"
         echo "$packages[@] installed [$Installed]"
         sudo dnf install -y "$packages[@]"
         sleep 0.5
         clear
     else
         export installed2="Ok"
         echo "$packages[@] $installed2"
     fi
done
fi
wget -q --show-progress https://downloads.apache.org/guacamole/$GUACAMOLE_VERSION/source/guacamole-server-$GUACAMOLE_VERSION.tar.gz
