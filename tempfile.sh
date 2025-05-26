# Install xRDP server
sudo apt update && sudo apt install -y xrdp dbus-x11
# Add self-signed certificate
sudo rm /etc/xrdp/cert.pem /etc/xrdp/key.pem
sudo openssl req -new -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes -out /etc/xrdp/cert.pem -keyout /etc/xrdp/key.pem
sudo chown root:xrdp /etc/xrdp/key.pem
sudo chmod 440 /etc/xrdp/key.pem
# Enable the RDP daemon
sudo systemctl enable xrdp
