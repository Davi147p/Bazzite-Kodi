#!/bin/bash
set -euo pipefail

source "/ctx/utility.sh"

install_session_switch_handler() {
    log_subsection "Installing session switch handler daemon"

    # Install the daemon script
    cp /ctx/components/system-scripts/session-switch-handler /usr/bin/
    chmod +x /usr/bin/session-switch-handler

    # Install the set content type script
    cp /ctx/components/system-scripts/set-content-type /usr/bin/
    chmod +x /usr/bin/set-content-type

    # Install systemd service
    cp /ctx/config/systemd/session-switch-handler.service /usr/lib/systemd/system/

    # Create SDDM override directory and install override
    mkdir -p /usr/lib/systemd/system/sddm.service.d
    cp /ctx/config/systemd/sddm.service.d/gaming-mode.conf /usr/lib/systemd/system/sddm.service.d/

    # Enable the service
    systemctl enable session-switch-handler.service

    log_success "Session switch handler installed"
}

install_session_request_scripts() {
    log_subsection "Installing session request scripts"

    # Install user-facing commands
    cp /ctx/components/system-scripts/request-kodi /usr/bin/
    cp /ctx/components/system-scripts/request-gamemode /usr/bin/

    chmod +x /usr/bin/request-kodi
    chmod +x /usr/bin/request-gamemode

    log_success "Session request scripts installed"
}

install_session_switch_handler
install_session_request_scripts

log_info ""
log_info "Session switching commands:"
log_info "  - Switch to Kodi: request-kodi"
log_info "  - Switch to Gaming: request-gamemode"
log_info "  - From Kodi UI: run kodi-request-gamemode"