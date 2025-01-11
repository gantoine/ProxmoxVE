#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: arcaneasada (gantoine)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://romm.app

# App Default Values
APP="RomM"
var_tags="media"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/romm ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "Installing jq..."
      apt-get install -y jq >/dev/null 2>&1
      echo "Installed jq..."
    fi

    msg_info "Updating ${APP}"
    systemctl stop romm
    RELEASE=$(curl -s https://api.github.com/repos/rommapp/romm/tags | jq --raw-output '.[0].name')
    TEMPD="$(mktemp -d)"
    cd "${TEMPD}"
    wget -q https://codeload.github.com/rommapp/romm/tar.gz/refs/tags/${RELEASE} -O - | tar -xz
    mv /opt/romm /opt/romm_bak
    mv rommapp-romm-*/* /opt/romm/
    mv /opt/romm_bak/.env /opt/romm
    mv /opt/romm_bak/server-files /opt/romm/server-files
    cd /opt/romm/backend
    poetry install --sync &>/dev/null
    cd ../frontend
    npm install &>/dev/null
    systemctl start romm
    msg_ok "Successfully Updated ${APP} to ${RELEASE}"
    rm -rf "${TEMPD}"
    rm -rf /opt/romm_bak
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5006${CL}"
