#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: gantoine
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  gpg \
  git \
  jq \
  build-essential \
  mariadb-server \
  libmariadb3 \
  libmariadb-dev \
  mariadb-connector-c \
  python3 \
  python3-pip \
  valkey \
  gcc \
  libc-dev \
  make \
  pcre-dev \
  zlib-dev \
  g++ \
  linux-headers \
  libmagic \
  libpq \
  p7zip \
  tzdata
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js Repository"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
msg_ok "Set up Node.js Repository"

msg_info "Installing Node.js"
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Installing Python Packages"
$STD pip3 install --upgrade pip gunicorn
$STD pip3 install poetry poetry-plugin-export

ln -s /usr/local/bin/poetry /usr/bin/poetry
ln -s /usr/bin/python3 /usr/bin/python
ln -s /usr/local/bin/gunicorn /usr/bin/gunicorn
msg_ok "Installed Python Packages"

msg_info "Installing RAHasher"
wget -q https://github.com/RetroAchievements/RALibretro/releases/download/1.8.0/RAHasher-x64-Linux-1.8.0.zip -O - | bsdtar -xvf- -C /tmp
mv /tmp/bin64/RAHasher /usr/bin/RAHasher
rm -rf /tmp/bin64
msg_ok "Installed RAHasher"

msg_info "Building nginx"
git clone https://github.com/evanmiller/mod_zip.git /tmp/mod_zip
git clone --branch "release-1.27.1" --depth 1 https://github.com/nginx/nginx.git /tmp/nginx
mv mod_zip-* /tmp/mod_zip
cd /tmp/mod_zip
git checkout 8e65b82c82c7890f67a6107271c127e9881b6313
cd ../nginx
./auto/configure --with-compat --add-dynamic-module=../mod_zip
make -f ./objs/Makefile modules
chmod 644 ./objs/ngx_http_zip_module.so
mv ./objs/ngx_http_zip_module.so /usr/lib/nginx/modules
rm -rf /tmp/mod_zip /tmp/nginx
msg_ok "Built nginx"

msg_info "Setting up Database"
DB_NAME=romm
DB_USER=romm
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD sudo mysql -u root -e "CREATE DATABASE $DB_NAME;"
$STD sudo mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password AS PASSWORD('$DB_PASS');"
$STD sudo mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
    echo "RomM-Credentials"
    echo "RomM Database User: $DB_USER"
    echo "RomM Database Password: $DB_PASS"
    echo "RomM Database Name: $DB_NAME"
} >> ~/romm.creds
msg_ok "Set up database"

RELEASE=$(curl -s https://api.github.com/repos/rommapp/romm/tags | jq --raw-output '.[0].name')
msg_info "Installing RomM v$RELEASE"
wget -q https://codeload.github.com/rommapp/romm/tar.gz/refs/tags/${RELEASE} -O - | tar -xz
mv romm-* /opt/romm
mkdir -p /opt/romm/server-files
chown -R root:root /opt/romm/server-files
chmod 755 /opt/romm/server-files

mkdir -p /opt/romm-data
mkdir -p /opt/romm-data/library/roms
mkdir -p /opt/romm-data/resources
mkdir -p /opt/romm-data/assets
mkdir -p /opt/romm-data/config

cat <<EOF > /opt/romm/.env
ROMM_BASE_PATH=/opt/romm-data
ROMM_AUTH_SECRET_KEY=$(openssl rand -base64 32)
IGDB_CLIENT_ID=
IGDB_CLIENT_SECRET=
MOBYGAMES_API_KEY=
STEAMGRIDDB_API_KEY=
EOF

cd /opt/romm/backend
$STD poetry install --only=main --no-ansi --no-interaction --no-root
$STD poetry export --without-hashes --without-urls -f requirements.txt --output requirements.txt
$STD pip install --no-cache-dir -r requirements.txt
$STD pip install .

cd /opt/romm/frontend
$STD npm ci
$STD npm run build
cp -r /opt/romm/frontend/dist/ /var/www/html
cp -r /opt/romm/frontend/assets/dashboard-icons /var/www/html/assets/dashboard-icons
cp -r /opt/romm/frontend/assets/default /var/www/html/assets/default
cp -r /opt/romm/frontend/assets/platforms /var/www/html/assets/platforms
cp -r /opt/romm/frontend/assets/scrappers /var/www/html/assets/scrappers
cp -r /opt/romm/frontend/assets/webrcade/feed /var/www/html/assets/webrcade/feed
cp -r /opt/romm/frontend/assets/emulatorjs /var/www/html/assets/emulatorjs
cp -r /opt/romm/frontend/assets/ruffle /var/www/html/assets/ruffle

mkdir -p /var/www/html/assets/romm
ln -s /opt/romm-data/resources /var/www/html/assets/romm/resources
ln -s /opt/romm-data/assets /var/www/html/assets/romm/assets

# Setup init script and config files
COPY /opt/romm/docker/nginx/js/ /etc/nginx/js/
COPY /opt/romm/docker/nginx/default.conf /etc/nginx/nginx.conf
msg_ok "Installed RomM"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/romm.service
[Unit]
Description=RomM Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/romm
EnvironmentFile=/opt/romm/.env
ExecStart=/opt/romm/docker/init_scripts/init
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now romm.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"
