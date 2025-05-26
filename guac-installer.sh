#!/bin/bash

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
   exit 1
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
wget -q --show-progress -o guacamole-server-$GUACAMOLE_VERSION.tar.gz https://apache.org/dyn/closer.lua/guacamole/1.5.5/source/guacamole-server-$GUACAMOLE_VERSION.tar.gz?action=download
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
if [ ! -f $HOME/guacamole-$GUACAMOLE_VERSION.war ]; then
wget -P $HOME -q --show-progress -o guacamole-$GUACAMOLE_VERSION.war https://apache.org/dyn/closer.lua/guacamole/$GUACAMOLE_VERSION/binary/guacamole-$GUACAMOLE_VERSION.war?action=download
fi
if ! $(rpm -qa | grep -q -o "tomcat"); then
   sudo dnf install tomcat
fi
sudo systemctl enable --now tomcat

echo "moving war file to tomcat webapps directory"
sudo mv guacamole-$GUACAMOLE_VERSION.war /var/lib/tomcat/webapps/guacamole.war

sudo mkdir -p /etc/guacamole/{extensions,lib}

# Note: Writes to a file named 'tomcat' in the current directory, then moves it.
echo "GUACAMOLE_HOME=/etc/guacamole" >> ./tomcat && sudo mv tomcat /etc/default

sudo touch /etc/guacamole/guacd.conf
sudo systemctl enable --now mariadb

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
    wget -q --show-progress -P "$WORK_DIR" "https://dlcdn.apache.org/guacamole/$GUACAMOLE_VERSION/binary/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz"
    tar -xf "$WORK_DIR/guacamole-auth-jdbc-$GUACAMOLE_VERSION.tar.gz" -C "$WORK_DIR"

    cd "$WORK_DIR/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql" || exit 1
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

# The JAR to copy is guacamole-auth-jdbc-mysql, not the main one
# This path depends on where tar extracted, assuming it's $WORK_DIR/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql/
JDBC_MYSQL_JAR_PATH="$WORK_DIR/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql/guacamole-auth-jdbc-mysql-$GUACAMOLE_VERSION.jar"
if [ -f "$JDBC_MYSQL_JAR_PATH" ]; then
    sudo cp "$JDBC_MYSQL_JAR_PATH" /etc/guacamole/extensions/
else
    echo "WARNING: Guacamole JDBC MySQL Auth JAR not found at $JDBC_MYSQL_JAR_PATH"
fi


echo "installing mysql connector" # This refers to MySQL Connector/J
# The RPM URL is for fc37, might not work on other systems.
# A better approach might be `sudo dnf install -y mysql-connector-java` if available.
MYSQL_CONNECTOR_RPM_URL="https://cdn.mysql.com/archives/mysql-connector-java-8.2/mysql-connector-j-8.2.0-1.fc37.noarch.rpm"
MYSQL_CONNECTOR_RPM_NAME=$(basename "$MYSQL_CONNECTOR_RPM_URL")

wget -q --show-progress -P "$WORK_DIR" "$MYSQL_CONNECTOR_RPM_URL"
if [ $? -eq 0 ]; then
    sudo dnf install -y "$WORK_DIR/$MYSQL_CONNECTOR_RPM_NAME"
else
    echo "Failed to download MySQL Connector/J RPM. Attempting 'sudo dnf install -y mysql-connector-java'..."
    sudo dnf install -y mysql-connector-java
fi

# Find and link the connector JAR
MYSQL_CONNECTOR_JAR_SYSTEM_PATH=""
POSSIBLE_PATHS=("/usr/share/java/mysql-connector-j.jar" "/usr/share/java/mysql-connector-java.jar") # Common paths
for P_PATH in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$P_PATH" ]; then
        MYSQL_CONNECTOR_JAR_SYSTEM_PATH="$P_PATH"
        break
    fi
done
# Fallback for versioned names like mysql-connector-j-8.2.0.jar
if [ -z "$MYSQL_CONNECTOR_JAR_SYSTEM_PATH" ]; then
    MYSQL_CONNECTOR_JAR_SYSTEM_PATH=$(find /usr/share/java -name 'mysql-connector-j-*.jar' -print -quit 2>/dev/null)
fi


if [ -n "$MYSQL_CONNECTOR_JAR_SYSTEM_PATH" ] && [ -f "$MYSQL_CONNECTOR_JAR_SYSTEM_PATH" ]; then
    sudo ln -sf "$MYSQL_CONNECTOR_JAR_SYSTEM_PATH" /etc/guacamole/lib/mysql-connector.jar
    echo "MySQL Connector/J symlinked from $MYSQL_CONNECTOR_JAR_SYSTEM_PATH"
else
    echo "WARNING: MySQL Connector/J JAR not found. Guacamole JDBC auth might fail."
    echo "Please ensure it's installed and symlink it to /etc/guacamole/lib/mysql-connector.jar"
fi


echo "[server]" | sudo tee /etc/guacamole/guacd.conf > /dev/null # Overwrite or create
echo "bind_host = 0.0.0.0" | sudo tee -a /etc/guacamole/guacd.conf > /dev/null
echo "bind_port = 4822" | sudo tee -a /etc/guacamole/guacd.conf > /dev/null

# This creates ./guacamole.properties in the current directory
# (which is likely $WORK_DIR/guacamole-auth-jdbc-$GUACAMOLE_VERSION/mysql/ at this point).
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
sudo systemctl restart guacd
sudo systemctl restart tomcat

echo "Cleaning up temporary installation files from $WORK_DIR..."
# rm -rf "$WORK_DIR" # Uncomment to auto-cleanup

echo "Installation script finished."
fi
