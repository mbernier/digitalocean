#!/bin/bash
# Complete DigitalOcean deployment script with interactive walkthrough
# This handles the entire process: droplet creation, domain setup, app deployment

# Default log level (0=quiet, 1=normal, 2=verbose, 3=debug)
LOG_LEVEL=1

# Parse command line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --check) SKIP_CHECKS=0 ;;
        --verbose|-v) LOG_LEVEL=2 ;;
        --debug|-d) LOG_LEVEL=3 ;;
        --quiet|-q) LOG_LEVEL=0 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Logging functions
log_debug() {
    [[ $LOG_LEVEL -ge 3 ]] && echo -e "\033[0;90m[DEBUG] $@\033[0m"
}

log_verbose() {
    [[ $LOG_LEVEL -ge 2 ]] && echo -e "\033[0;94m[INFO] $@\033[0m"
}

log_info() {
    [[ $LOG_LEVEL -ge 1 ]] && echo -e "$@"
}

log_error() {
    echo -e "\033[0;31m[ERROR] $@\033[0m"
}

# Load the core functions and utilities
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
log_debug "Script directory: $DIR"

log_verbose "Loading utility scripts..."
source "$DIR/lib/utils.sh"
source "$DIR/lib/droplet.sh"
source "$DIR/lib/domain.sh"
source "$DIR/lib/deploy.sh"
source "$DIR/lib/data_migrate.sh"
source "$DIR/lib/cloud_init.sh"

# Export logging functions so they can be used in the sourced scripts
export -f log_debug log_verbose log_info log_error
export LOG_LEVEL

# Configuration file
CONFIG_FILE="$DIR/.do_deploy.conf"
log_debug "Config file path: $CONFIG_FILE"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    log_verbose "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Sanity check loaded configuration
    if [ ! -z "$DROPLET_IP" ]; then
        log_debug "Found droplet IP in config: $DROPLET_IP"
        
        # Validate IP format (basic check)
        if ! [[ $DROPLET_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid IP address format in config: $DROPLET_IP"
            echo -e "${YELLOW}The IP address in your configuration file doesn't look valid.${NC}"
            echo -e "You may need to edit or remove the config file: $CONFIG_FILE"
            DROPLET_IP=""
        else
            # Check if the droplet is actually reachable and get deployment information
            log_verbose "Checking droplet connectivity and deployment status..."
            if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "exit" &>/dev/null; then
                # Check for docker
                HAS_DOCKER=false
                if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "command -v docker" &>/dev/null; then
                    HAS_DOCKER=true
                    log_verbose "Docker detected on droplet"
                    
                    # Check for docker-compose
                    if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "docker compose version" &>/dev/null || ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "command -v docker-compose" &>/dev/null; then
                        if [ -z "$DEPLOYMENT_TYPE" ] || [ "$DEPLOYMENT_TYPE" != "docker-compose" ]; then
                            log_verbose "Docker Compose detected, updating deployment type"
                            DEPLOYMENT_TYPE="docker-compose"
                            
                            # Update the project configuration if it exists
                            if [ -f "$DIR/.do_deploy.project" ]; then
                                sed -i.bak "s/DEPLOYMENT_TYPE=.*/DEPLOYMENT_TYPE=\"docker-compose\"/" "$DIR/.do_deploy.project"
                            fi
                        fi
                    elif [ -z "$DEPLOYMENT_TYPE" ]; then
                        log_verbose "Docker detected but no Compose, setting deployment type to docker"
                        DEPLOYMENT_TYPE="docker"
                    fi
                fi
                
                # Check for app directory
                if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "test -d ${APP_ROOT:-/root/app}" &>/dev/null; then
                    log_verbose "Application directory detected on droplet"
                    
                    # Check for app configuration
                    if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "test -f ${APP_ROOT:-/root/app}/.env" &>/dev/null; then
                        log_verbose "Application configuration (.env) detected"
                    fi
                fi
            fi
        fi
    else
        log_verbose "No droplet IP found in config"
    fi
else
    log_verbose "No existing configuration found at $CONFIG_FILE"
fi

# Skip all checks by default
SKIP_CHECKS=1

# Function to run initial checks
run_initial_checks() {
    log_verbose "Running initial system checks..."
    # Run startup checks
    check_prerequisites
    check_auth
    check_ssh_keys
    log_verbose "System checks completed"
}

# Show the welcome screen and initial configuration wizard
log_verbose "Displaying welcome screen"
show_welcome

# Only run checks if requested
if [ $SKIP_CHECKS -eq 0 ]; then
    log_verbose "Checks requested, running initial checks..."
    run_initial_checks
fi

if [ ! -f "$DIR/.do_deploy.project" ]; then
    log_verbose "No project configuration found, running setup wizard..."
    initial_setup_wizard
else
    # If project config exists but doesn't have language settings, prompt for them
    source "$DIR/.do_deploy.project"
    if [ -z "$SELECTED_LANGUAGES" ] || [ -z "$SUGGESTED_PACKAGES" ]; then
        log_verbose "Project config exists but language settings are missing..."
        echo -e "${GREEN}Let's identify programming languages used in your project...${NC}"
        language_packages_menu
    fi
fi

# Load project-specific config
if [ -f "$DIR/.do_deploy.project" ]; then
    log_verbose "Loading project configuration from $DIR/.do_deploy.project"
    source "$DIR/.do_deploy.project"
    log_debug "Project configuration: PROJECT_NAME=$PROJECT_NAME, DEPLOYMENT_TYPE=$DEPLOYMENT_TYPE"
fi

# Main menu loop
main_menu() {
    log_verbose "Entering main menu"
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
            if [ ! -z "$DEPLOYMENT_TYPE" ]; then
                echo -e "  Deployment: ${YELLOW}$DEPLOYMENT_TYPE${NC}"
            fi
            echo
        fi
        
        # Menu options - dynamically change based on existing configuration
        if [ ! -z "$DROPLET_IP" ]; then
            # Droplet exists - show management options
            MENU_OPTIONS=(
                "Manage droplet"
                "Check deployment status"
                "Set up domain configuration"
                "Deploy application"
                "Migrate data"
                "Advanced cloud-init provisioning" 
                "Configure web server"
                "Manage project settings"
                "Run system checks"
                "Quit"
            )
        else
            # No droplet exists - show creation option
            MENU_OPTIONS=(
                "Create a new droplet"
                "Set up domain configuration"
                "Deploy application"
                "Migrate data"
                "Advanced cloud-init provisioning" 
                "Configure web server"
                "Manage project settings"
                "Run system checks"
                "Quit"
            )
        fi
        
        select_from_menu "Select an action" "${MENU_OPTIONS[@]}"
        MENU_CHOICE=$?
        log_debug "Selected menu option: $MENU_CHOICE"
        
        case $MENU_CHOICE in
            0) 
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Managing existing droplet..."
                    manage_droplet
                else
                    log_verbose "Creating a new droplet..."
                    create_droplet 
                fi
                ;;
            1)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Checking deployment status..."
                    deployment_status
                else
                    log_verbose "Setting up domain configuration..."
                    setup_domain
                fi
                ;;
            2)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Setting up domain configuration..."
                    setup_domain
                else 
                    log_verbose "Deploying application..."
                    deploy_app
                fi
                ;;
            3)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Deploying application..."
                    deploy_app
                else
                    log_verbose "Migrating data..."
                    migrate_data
                fi
                ;;
            4)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Migrating data..."
                    migrate_data
                else
                    log_verbose "Opening cloud-init menu..."
                    cloud_init_menu
                fi
                ;;
            5)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Opening cloud-init menu..."
                    cloud_init_menu
                else
                    log_verbose "Configuring web server..."
                    webserver_menu
                fi
                ;;
            6)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Configuring web server..."
                    webserver_menu
                else
                    log_verbose "Managing project settings..."
                    project_settings_menu
                fi
                ;;
            7)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Managing project settings..."
                    project_settings_menu
                else
                    log_verbose "Running system checks..."
                    run_initial_checks
                fi
                ;;
            8)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Running system checks..."
                    run_initial_checks
                else
                    log_verbose "Exiting script..."
                    echo -e "${GREEN}Thank you for using the DigitalOcean Deployment Wizard!${NC}"
                    exit 0
                fi
                ;;
            9)
                if [ ! -z "$DROPLET_IP" ]; then
                    log_verbose "Exiting script..."
                    echo -e "${GREEN}Thank you for using the DigitalOcean Deployment Wizard!${NC}"
                    exit 0
                fi
                ;;
        esac
    done
}

# Start the script
log_verbose "Starting main menu..."
main_menu