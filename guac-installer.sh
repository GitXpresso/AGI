#!/bin/bash
GUACAMOLE_VERSION="1.5.5" 

if [ -d /etc/dnf ]; then
packages=("wget" "cairo-devel" "libjpeg-devel" "libpng-devel" "uuid-devel" "freerdp-devel" "pango-devel" "libssh2-devel" "libtelnet-devel" "libvncserver-devel" "pulseaudio-libs-devel" "openssl-devel" "libvorbis-devel" "libwebsockets-devel" "tomcat-native" "tomcat" "tar" "mariadb-server")
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
sudo mkdir -p /etc/guacamole/{extensions,lib}
echo "GUACAMOLE_HOME=/etc/guacamole" >> tomcat && sudo mv tomcat /etc/default
cat << EOF >./guacamole.properties
# Guacamole properties

# Hostname and port of guacamole proxy
guacd-hostname: localhost
guacd-port: 4822

# Auth provider class (authenticates user credentials)
# Example LDAP authentication
#auth-provider: net.sourceforge.guacamole.net.basic.BasicFileAuthenticationProvider
# Example MySQL authentication
#auth-provider: net.sourceforge.guacamole.net.mysql.MySQLAuthenticationProvider
# Example JDBC authentication
#auth-provider: net.sourceforge.guacamole.net.jdbc.JDBCAuthenticationProvider

# LDAP properties
#ldap-hostname: ldap.example.com
#ldap-port: 389
#ldap-user-base-dn: dc=example,dc=com
#ldap-username-attribute: uid
#ldap-encryption-method: none
#ldap-search-bind-dn: cn=admin,dc=example,dc=com
#ldap-search-bind-password: password

# MySQL properties
#mysql-hostname: localhost
#mysql-port: 3306
#mysql-database: guacamole_db
#mysql-username: guacamole_user
#mysql-password: password

# JDBC properties
#jdbc-driver: com.mysql.jdbc.Driver
#jdbc-url: jdbc:mysql://localhost:3306/guacamole_db
#jdbc-username: guacamole_user
#jdbc-password: password

# Guacamole authentication
# Example basic file authentication
#basic-user-mapping: /etc/guacamole/user-mapping.xml

# Guacamole properties
# The value of "guacd-hostname" is ignored if using "guacd-socket".
#guacd-hostname: localhost
#guacd-port: 4822
#guacd-socket: /var/run/guacd/guacd.sock

# Enable SSL
#guacamole-ssl: true
#guacamole-ssl-certificate: /etc/pki/tls/certs/localhost.crt
#guacamole-ssl-key: /etc/pki/tls/private/localhost.key
#guacamole-ssl-key-password: password

# WebSocket configuration
#web-socket-support: true
#web-socket-maximum-connections: 100

# Token parameter name
#token-parameter-name: token

# User permissions
#admin-group: admin
#user-group: users

# Disable user input history
#history-size: 0
EOF
sudo cp guacamole.properties /etc/guacamole/guacamole.properties
sudo touch /etc/guacamole/guacd.conf
sudo systemctl enable --now mariadb
