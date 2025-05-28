#!/bin/bash
blue_bold=$(printf '\033[1;34m')
orange_bold=$(printf '\033[48:2:255:165:0m%s\033[m')
red_bold=$(printf '\033[1;31m')
ubuntu_orange_bold=$(printf '\033[1;38;2;255;255;255;48;2;255;165;0m')
fedora_blue_bold=$(printf '\033[1;96m') 
no_color=$(printf '\033[0m') 
GUACAMOLE_VERSION="1.5.5"

# This initial check, as written, will likely cause the script to exit immediately
# for both root and non-root users, because `[ $(id -u) ]` evaluates to true
# if `id -u` outputs any non-empty string (which it always does).
if [ $(id -u ) -gt 0 ]; then
    echo "run this script as root (use sudo)"
    exit 1
fi
if systemd-detect-virt --container | grep -q -o "docker"; then
   echo "your in a container, exiting..."
   echo "You do you want to use systemctl python file for containers? (yes/no): " yorno
   if [ $yorno == "y" ] || [ $yorno == "yes" ]; then
       sudo curl -o /bin/systemctl https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py && sudo chmod -R 755 /bin/systemctl > /dev/null
       export systemctlcmd="/bin/systemctl"
   elif [ "$yorno" == "n" ] || [ "$yorno" == "no" ]; then
        echo "not running an alternative to systemd in containized environment exiting..."
        exit 1 
   else
        export systemctlcmd="systemctl"
   fi
if [ -d /etc/dnf ]; then
    packages=("wget" "cairo-devel" "libjpeg-devel" "libpng-devel" "uuid-devel" "freerdp-devel" "pango-devel" "libssh2-devel" "libtelnet-devel" "libvncserver-devel" "pulseaudio-libs-devel" "openssl-devel" "libvorbis-devel" "libwebsockets-devel" "tomcat-native" "mariadb-server")
    for dnfpackages in "${packages[@]}"; do
        rpm -qa | grep "$dnfpackages" > /dev/null 2>&1
        if [ $? -ne 0 ]; then

            echo "$dnfpackages is not installed"
            sudo dnf install -y "$dnfpackages"
        else
            echo "$dnfpackages is installed"
        fi
    done
clear

if [ ! $(pwd) == "$HOME" ]; then
    cd $HOME # Quoting "$HOME" is safer: cd "$HOME"
fi
if [ ! rpm -qa | grep -q tomcat-lib ]; then
   sudo dnf install tomcat
fi
echo "Downloading tarball"
if [ ! -d $HOME/guacamole-server-$GUACAMOLE_VERSION ]; then
wget -q --show-progress -O guacamole-server-$GUACAMOLE_VERSION.tar.gz https://apache.org/dyn/closer.lua/guacamole/1.5.5/source/guacamole-server-$GUACAMOLE_VERSION.tar.gz?action=download
fi
tar -xf guacamole-server-$GUACAMOLE_VERSION.tar.gz 
if [ ! $(pwd) == $HOME/guacamole-server-$GUACAMOLE_VERSION ]; then
cd guacamole-server-$GUACAMOLE_VERSION
fi
echo "configuring..."
./configure --with-systemd-dir=/etc/systemd/system/ --disable-dependency-tracking
echo "running make commands"
make
sudo make install
sudo ldconfig
clear

echo "download war file..."
#wget -q --show-progress https://downloads.apache.org/guacamole/$GUACAMOLE_VERSION/binary/guacamole-$GUACAMOLE_VERSION.war
currentworkingdir=$(pwd)
if [ ! -f $HOME/guacamole-$GUACAMOLE_VERSION.war ]; then
cd $HOME
wget -q --show-progress -O guacamole-$GUACAMOLE_VERSION.war https://apache.org/dyn/closer.lua/guacamole/$GUACAMOLE_VERSION/binary/guacamole-$GUACAMOLE_VERSION.war?action=download
cd $currentworkingdir
fi
if ! $(rpm -qa | grep -q -o "tomcat-lib"); then
   sudo dnf install tomcat
fi
sudo $systemctlcmd enable --now tomcat

echo "moving war file to tomcat webapps directory"
sudo mv $HOME/guacamole-$GUACAMOLE_VERSION.war /var/lib/tomcat/webapps/guacamole.war

sudo mkdir -p /etc/guacamole/{extensions,lib}

# Note: Writes to a file named 'tomcat' in the current directory, then moves it.
echo "GUACAMOLE_HOME=/etc/guacamole" >> ./tomcat && sudo mv tomcat /etc/default

sudo touch /etc/guacamole/guacd.conf
sudo $systemctlcmd enable --now mariadb

# Check if mysql root has a password.
mysql -u root -e "QUIT" &> /dev/null
if [ $? -gt 0 ]; then
    echo "Initial MySQL root login failed. This might mean a password is set, or root cannot login without one yet."
    echo "Attempting to set/reset MySQL root password."
    read -s -p "Enter a NEW password for the MySQL 'root'@'localhost' user: " mysqlpassword
    echo # Newline after read -s
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysqlpassword}';"
    if [ $? -ne 0 ]; then
        echo "Failed to set MySQL root password. Manual intervention might be required."
        echo "Attempting to proceed, but further MySQL operations might fail if root password wasn't set."
    fi
    sudo mysql -u root -p"${mysqlpassword}" -e "DROP USER IF EXISTS ''@'localhost';"
    sudo mysql -u root -p"${mysqlpassword}" -e "DROP USER IF EXISTS ''@'$(hostname)';"
    sudo mysql -u root -p"${mysqlpassword}" -e "DROP DATABASE IF EXISTS test;"
    sudo mysql -u root -p"${mysqlpassword}" -e "FLUSH PRIVILEGES;"

    sudo mysql -u root -p"${mysqlpassword}" -e "CREATE DATABASE IF NOT EXISTS guacamole_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    wget -q --show-progress -P $HOME "https://dlcdn.apache.org/guacamole/$GUACAMOLE_VERSION/binary/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz"
    tar -xf $HOME/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz -C ~/

    cd $HOME/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql; sudo cat schema/*.sql | sudo mysql -u root -p"${mysqlpassword}" guacamole_db

    # Read password *before* using it
    read -s -p "Set a password for the new MySQL user 'guacamole_user': " mysqlguacpass
    echo # Newline
    while [ -z "$mysqlguacpass" ]; do
        read -s -p "Password cannot be empty. Set a password for 'guacamole_user': " mysqlguacpass
        echo
    done
    sudo mysql -u root -p"${mysqlpassword}" -e "CREATE USER IF NOT EXISTS 'guacamole_user'@'localhost' IDENTIFIED BY '$mysqlguacpass';"
    # Ensure password is set/updated even if user exists
    sudo mysql -u root -p"${mysqlpassword}" -e "ALTER USER 'guacamole_user'@'localhost' IDENTIFIED BY '$mysqlguacpass';"
    sudo mysql -u root -p"${mysqlpassword}" -e "GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';"
    sudo mysql -u root -p"${mysqlpassword}" -e "FLUSH PRIVILEGES;"
else
    echo "MySQL root login succeeded (possibly via socket auth or no password)."
    echo "If MySQL root already has a password, you'll be prompted for it for subsequent operations."
    # Original script read $rootpassword, which is incorrect. Should be rootpassword.
    read -s -p "Enter the current password for the MySQL 'root'@'localhost' user (or leave blank if none/using socket auth): " rootpassword
    echo # Newline

    MYSQL_AUTH_OPT=""
    if [ -n "$rootpassword" ]; then
        MYSQL_AUTH_OPT="--password=$rootpassword"
    fi

    # Test connection with provided password (if any)
    # Using sudo mysql as it might be socket auth that succeeded initially
    if ! sudo mysql -u root $MYSQL_AUTH_OPT -e "SELECT 1;" > /dev/null 2>&1; then
        echo "Failed to connect to MySQL with provided credentials or via sudo. Exiting."
        exit 1
    fi
    
    sudo mysql -u root $MYSQL_AUTH_OPT -e "DROP USER IF EXISTS ''@'localhost';"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "DROP USER IF EXISTS ''@'$(hostname)';"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "DROP DATABASE IF EXISTS test;"
    # CREATE DATABASE was missing in this branch in the original script
    sudo mysql -u root $MYSQL_AUTH_OPT -e "CREATE DATABASE IF NOT EXISTS guacamole_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "FLUSH PRIVILEGES;"

    # Downloads to WORK_DIR
    wget -q --show-progress -P "$HOME" "https://dlcdn.apache.org/guacamole/$GUACAMOLE_VERSION/binary/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz"
    tar -xf $HOME/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz -C $HOME

    cd $HOME/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql; sudo cat schema/*.sql | sudo mysql -u root $MYSQL_AUTH_OPT guacamole_db
    # Corrected schema import
    sudo cat schema/*.sql | sudo mysql -u root $MYSQL_AUTH_OPT guacamole_db

    read -s -p "Set a password for the new MySQL user 'guacamole_user': " mysqlguacpass
    echo # Newline
    while [ -z "$mysqlguacpass" ]; do
        read -s -p "Password cannot be empty. Set a password for 'guacamole_user': " mysqlguacpass
        echo
    done
    sudo mysql -u root $MYSQL_AUTH_OPT -e "CREATE USER IF NOT EXISTS 'guacamole_user'@'localhost' IDENTIFIED BY '$mysqlguacpass';"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "ALTER USER 'guacamole_user'@'localhost' IDENTIFIED BY '$mysqlguacpass';"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';"
    sudo mysql -u root $MYSQL_AUTH_OPT -e "FLUSH PRIVILEGES;"
fi
if [ ! -f guacamole-auth-jdbc-mysql-$GUCAMOLE_VERSION.jar ]; then
 sudo cp guacamole-auth-jdbc-mysql-$GUCAMOLE_VERSION.jar /etc/guacamole/extensions/
fi

if [ ! $( rpm -qa | grep -o mysql-connector) ]; then
sudo dnf install https://cdn.mysql.com/archives/mysql-connector-java-8.2/mysql-connector-j-8.2.0-1.fc37.noarch.rpm
fi
if [ ! -f /etc/guacamole/lib/mysql-connector-java.jar ]; then
  sudo cp /usr/share/java/mysql-connector-java.jar /etc/guacamole/lib/mysql-connector.jar
fi
echo "[server]" | sudo tee /etc/guacamole/guacd.conf > /dev/null # Overwrite or create
echo "bind_host = 0.0.0.0" | sudo tee -a /etc/guacamole/guacd.conf > /dev/null
echo "bind_port = 4822" | sudo tee -a /etc/guacamole/guacd.conf > /dev/null

# This creates ./guacamole.properties in the current directory
# (which is likely $HOME/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql/ at this point).
# It should be created directly in /etc/guacamole or created then moved.
# Creating it directly in /etc/guacamole:
sudo tee /etc/guacamole/guacamole.properties > /dev/null <<EOF
# MySQL properties
mysql-hostname: localhost
mysql-port: 3306
mysql-database: guacamole_db
mysql-username: guacamole_user
mysql-password: ${mysqlguacpass} # This variable must be set from one of the branches above

# Guacamole server settings
guacd-hostname: localhost
guacd-port: 4822

# Auth provider class for JDBC
auth-provider: org.apache.guacamole.auth.jdbc.JDBCAuthModule

# JDBC driver class
jdbc-driver: com.mysql.cj.jdbc.Driver # For modern MySQL Connector/J
# For older: jdbc-driver: com.mysql.jdbc.Driver

# JDBC URL
jdbc-url: jdbc:mysql://localhost:3306/guacamole_db?serverTimezone=UTC&allowPublicKeyRetrieval=true&useSSL=false
EOF
# Secure the properties file
sudo chmod 600 /etc/guacamole/guacamole.properties
sudo chown root:tomcat /etc/guacamole/guacamole.properties # Tomcat needs to read this. Or just root:root if Tomcat runs as root.

# The guacamole.properties.example was never used or created by the script.
# The above tee command directly creates /etc/guacamole/guacamole.properties.
# So, the following mv/cp lines are removed as they are not applicable with the direct creation.
# sudo mv guacamole.properties.example ~/ && sudo cp ~/guacamole.properties.example /etc/guacamole/guacamole.properties

echo "restarting guacd and tomcat to apply the changes"
sudo $systemctlcmd restart guacd
sudo $systemctlcmd restart tomcat

echo "Cleaning up temporary installation files from $HOME..."
# rm -rf "$HOME" # Uncomment to auto-cleanup

echo "Installation script finished."

else
   oschecker=$(grep /etc/*release &> /dev/null)
   if [ grep -i "Ubuntu" /etc/*release &> /dev/null ]; then
   export $osname="Ubuntu"
   echo "You are on $osname which this script
fi
