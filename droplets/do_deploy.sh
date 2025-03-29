#!/bin/bash
# Complete DigitalOcean deployment script with interactive walkthrough
# This handles the entire process: droplet creation, domain setup, app deployment

# Load the core functions and utilities
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/lib/utils.sh"
source "$DIR/lib/droplet.sh"
source "$DIR/lib/domain.sh"
source "$DIR/lib/deploy.sh"
source "$DIR/lib/data_migrate.sh"
source "$DIR/lib/cloud_init.sh"

# Configuration file
CONFIG_FILE="$DIR/.do_deploy.conf"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Run startup checks
check_prerequisites
check_auth
check_ssh_keys

# Show the welcome screen and initial configuration wizard
show_welcome
if [ ! -f "$DIR/.do_deploy.project" ]; then
    initial_setup_wizard
fi

# Load project-specific config
source "$DIR/.do_deploy.project"

# Main menu loop
main_menu() {
    while true; do
        show_header "DigitalOcean Deployment Wizard"
        
        # Check if droplet is already created
        if [ ! -z "$DROPLET_IP" ]; then
            echo -e "${GREEN}Current Configuration:${NC}"
            echo -e "  Droplet: ${YELLOW}$DROPLET_NAME${NC} (${YELLOW}$DROPLET_IP${NC})"
            if [ ! -z "$DOMAIN_NAME" ]; then
                echo -e "  Domain:  ${YELLOW}$DOMAIN_NAME${NC}"
            fi
            echo -e "  Project: ${YELLOW}$PROJECT_NAME${NC}"
            echo
        fi
        
        # Menu options
        MENU_OPTIONS=(
            "Create a new droplet"
            "Set up domain configuration"
            "Deploy application"
            "Migrate data"
            "Advanced cloud-init provisioning"
            "Configure web server"
            "Manage project settings"
            "Quit"
        )
        
        select_from_menu "Select an action" "${MENU_OPTIONS[@]}"
        MENU_CHOICE=$?
        
        case $MENU_CHOICE in
            0) create_droplet ;;
            1) setup_domain ;;
            2) deploy_app ;;
            3) migrate_data ;;
            4) cloud_init_menu ;;
            5) webserver_menu ;;
            6) project_settings_menu ;;
            7) 
                echo -e "${GREEN}Thank you for using the DigitalOcean Deployment Wizard!${NC}"
                exit 0
                ;;
        esac
    done
}

# Start the script
main_menu
