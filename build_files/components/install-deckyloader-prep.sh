#!/bin/bash
set -euo pipefail

source "/ctx/utility.sh"

prepare_deckyloader() {
    log_subsection "Preparing DeckyLoader components"

    # Install jq dependency if not already installed
    if ! command -v jq &>/dev/null; then
        dnf install -y jq
    fi

    # Create staging directory
    mkdir -p /usr/share/decky-loader-stage

    # Download latest DeckyLoader
    log_info "Fetching latest DeckyLoader release info..."
    RELEASE=$(curl -s 'https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases' | jq -r '[.[] | select(.prerelease == false)] | first')
    VERSION=$(jq -r '.tag_name' <<< ${RELEASE})
    DOWNLOADURL=$(jq -r '.assets[].browser_download_url | select(endswith("PluginLoader"))' <<< ${RELEASE})

    log_info "Downloading DeckyLoader $VERSION..."
    curl -L $DOWNLOADURL --output /usr/share/decky-loader-stage/PluginLoader
    chmod +x /usr/share/decky-loader-stage/PluginLoader
    echo $VERSION > /usr/share/decky-loader-stage/.loader.version

    # Download service files
    log_info "Downloading DeckyLoader service files..."
    curl -L https://raw.githubusercontent.com/SteamDeckHomebrew/decky-loader/main/dist/plugin_loader-release.service \
        --output /usr/share/decky-loader-stage/plugin_loader-release.service

    # Create backup service template
    cat > /usr/share/decky-loader-stage/plugin_loader-backup.service <<- 'EOM'
[Unit]
Description=SteamDeck Plugin Loader
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=always
ExecStart=${HOMEBREW_FOLDER}/services/PluginLoader
WorkingDirectory=${HOMEBREW_FOLDER}/services
KillSignal=SIGKILL
Environment=PLUGIN_PATH=${HOMEBREW_FOLDER}/plugins
Environment=LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOM

    log_success "DeckyLoader $VERSION staged successfully"
}

prepare_kodilauncher() {
    log_subsection "Preparing KodiLauncher plugin"

    # Get latest version info
    local api_url="https://api.github.com/repos/Blahkaey/KodiLauncher/releases/latest"
    local version=$(curl -s "$api_url" | grep '"tag_name"' | cut -d'"' -f4)

    if [ -z "$version" ]; then
        log_error "Failed to fetch KodiLauncher version"
        return 1
    fi

    log_info "Downloading KodiLauncher $version..."
    wget -q "https://github.com/Blahkaey/KodiLauncher/releases/latest/download/KodiLauncher.zip" \
        -O /usr/share/decky-loader-stage/KodiLauncher.zip

    # Verify download
    if [ ! -f /usr/share/decky-loader-stage/KodiLauncher.zip ]; then
        log_error "Failed to download KodiLauncher"
        return 1
    fi

    echo "$version" > /usr/share/decky-loader-stage/.kodilauncher.version

    log_success "KodiLauncher $version staged successfully"
}

# Create first-boot deployment script
create_deployment_script() {
    log_subsection "Creating deployment script"

    cat > /usr/bin/deploy-deckyloader <<- 'EOF'
#!/bin/bash
set -euo pipefail

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] DECKY-DEPLOY: $@" | systemd-cat -t decky-deploy -p info
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] DECKY-DEPLOY ERROR: $@" | systemd-cat -t decky-deploy -p err
}

deploy_for_user() {
    local main_user="$1"
    local user_home=$(getent passwd "$main_user" | cut -d: -f6)
    local homebrew_folder="${user_home}/homebrew"

    log_info "Deploying DeckyLoader for user $main_user (home: $user_home)"

    # Create symlink if needed (for compatibility)
    if [ ! -L "/home/deck" ] && [ ! -e "/home/deck" ] && [ "$user_home" != "/home/deck" ]; then
        log_info "Creating /home/deck symlink to $user_home"
        ln -sf "$user_home" /home/deck
    fi

    # Create directory structure
    sudo -u "$main_user" mkdir -p "${homebrew_folder}/services"
    sudo -u "$main_user" mkdir -p "${homebrew_folder}/plugins"
    sudo -u "$main_user" mkdir -p "${user_home}/.steam/steam"
    sudo -u "$main_user" touch "${user_home}/.steam/steam/.cef-enable-remote-debugging"

    # Also for flatpak Steam
    if [ -d "${user_home}/.var/app/com.valvesoftware.Steam/data/Steam/" ]; then
        sudo -u "$main_user" touch "${user_home}/.var/app/com.valvesoftware.Steam/data/Steam/.cef-enable-remote-debugging"
    fi

    # Copy pre-downloaded PluginLoader
    cp /usr/share/decky-loader-stage/PluginLoader "${homebrew_folder}/services/"
    cp /usr/share/decky-loader-stage/.loader.version "${homebrew_folder}/services/"

    # Set ownership
    chown "$main_user:$main_user" "${homebrew_folder}/services/PluginLoader"
    chown "$main_user:$main_user" "${homebrew_folder}/services/.loader.version"

    # Set SELinux context if needed
    if command -v getenforce &>/dev/null && getenforce | grep -q "Enforcing"; then
        log_info "Setting SELinux context..."
        chcon -t bin_t "${homebrew_folder}/services/PluginLoader" 2>/dev/null || {
            log_error "Failed to set SELinux context"
        }
    fi

    # Deploy service file
    if [ -f /usr/share/decky-loader-stage/plugin_loader-release.service ]; then
        log_info "Using release service file"
        cp /usr/share/decky-loader-stage/plugin_loader-release.service /etc/systemd/system/plugin_loader.service
    else
        log_info "Using backup service file"
        cp /usr/share/decky-loader-stage/plugin_loader-backup.service /etc/systemd/system/plugin_loader.service
    fi

    # Update service file with actual paths
    sed -i "s|\${HOMEBREW_FOLDER}|${homebrew_folder}|g" /etc/systemd/system/plugin_loader.service

    # Copy service files to homebrew for reference
    mkdir -p "${homebrew_folder}/services/.systemd"
    cp /usr/share/decky-loader-stage/plugin_loader-*.service "${homebrew_folder}/services/.systemd/"
    chown -R "$main_user:$main_user" "${homebrew_folder}/services/.systemd"

    # Deploy KodiLauncher plugin
    log_info "Deploying KodiLauncher plugin..."
    local plugin_dir="${homebrew_folder}/plugins/KodiLauncher"

    if [ -f /usr/share/decky-loader-stage/KodiLauncher.zip ]; then
        mkdir -p "$plugin_dir"
        unzip -q /usr/share/decky-loader-stage/KodiLauncher.zip -d "$plugin_dir"
        chown -R "$main_user:$main_user" "$plugin_dir"

        # Copy version info
        cp /usr/share/decky-loader-stage/.kodilauncher.version /var/lib/kodi/.kodilauncher-version
        chown kodi:kodi /var/lib/kodi/.kodilauncher-version

        log_info "KodiLauncher deployed successfully"
    else
        log_error "KodiLauncher.zip not found in staging area"
    fi

    # Final ownership fix
    chown -R "$main_user:$main_user" "$homebrew_folder"

    # Enable and start service
    systemctl daemon-reload
    systemctl enable plugin_loader.service

    # Don't start immediately if we're in first boot
    if [ -z "${FIRSTBOOT:-}" ]; then
        systemctl start plugin_loader.service
    else
        log_info "Deferring plugin_loader start until after first boot"
    fi

    log_info "DeckyLoader deployment completed"
}

# Main execution
main_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -1)
if [ -z "$main_user" ]; then
    log_error "Could not find main user"
    exit 1
fi

deploy_for_user "$main_user"
EOF

    chmod +x /usr/bin/deploy-deckyloader

    log_success "Deployment script created"
}

# Main execution
main() {
    log_section "Pre-staging DeckyLoader and KodiLauncher"

    prepare_deckyloader
    prepare_kodilauncher
    create_deployment_script

    log_success "DeckyLoader components pre-staged successfully"
}

main "$@"
