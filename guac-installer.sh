#!/bin/bash

if [ -d /etc/dnf ]; then
packages=("wget" "cairo-devel" "libjpeg-devel" "libpng-devel" "uuid-devel" "freerdp-devel" "pango-devel" "libssh2-devel" "libtelnet-devel" "libvncserver-devel" "pulseaudio-libs-devel" "openssl-devel" "libvorbis-devel" "libwebsockets-devel" "tomcat-native" "tomcat")
for dnfpackages in "$(packages[@])'; do
     sudo dnf list installed | grep "$packages[@]" > /dev/null 2>&1
     if [ $? -ne 0 ]; then
         echo "$packages[@] is not installed"
         sudo dnf install -y "$packages[@]"
     else
         echo "$packages[@] is installed"
     fi
done
fi
