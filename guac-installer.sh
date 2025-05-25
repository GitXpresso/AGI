#!/bin/bash
GUACAMOLE_VERSION="1.5.5" 

if [ -d /etc/dnf ]; then
packages=("wget" "cairo-devel" "libjpeg-devel" "libpng-devel" "uuid-devel" "freerdp-devel" "pango-devel" "libssh2-devel" "libtelnet-devel" "libvncserver-devel" "pulseaudio-libs-devel" "openssl-devel" "libvorbis-devel" "libwebsockets-devel" "tomcat-native" "tomcat" "tar")
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
if [ ! $( pwd ) == "$HOME" ]; then
   cd $HOME
fi
echo "Downloading tarball"
wget -q --show-progress https://downloads.apache.org/guacamole/$GUACAMOLE_VERSION/source/guacamole-server-$GUACAMOLE_VERSION.tar.gz
tar -xf guacamole-server-$GUACAMOLE_VERSION.tar.gz f
cd guacamole-server-$GUACAMOLE_VERSION
echo "configuring..."
./configure --with-systemd-dir=/etc/systemd/system/ --disable-dependency-tracking
echo "running make commands"
make
sudo make install
sudo ldconfig
clear
echo "download war file..."
wget -q --show-progress https://downloads.apache.org/guacamole/$GUACAMOLE_VERSION/binary/guacamole-$GUACAMOLE_VERSION.war
sudo systemctl enable --now tomcat
if sudo systemctl is-active tomcat | grep active; then
   echo "tomcat service is active"
fi
echo "moving war file to tomcat webapps directory"
sudo mv guacamole-$GUACAMOLE_VERSION.war /var/lib/tomcat/webapps/guacamole.war
sudo systemctl restart tomcat
