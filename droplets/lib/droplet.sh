#!/bin/bash
# Droplet creation functions

# Create a new droplet
create_droplet() {
    # Default values
    DEFAULT_NAME="app-$(date +%Y%m%d)"
    
    # Array of options for regions, sizes, and images
    REGIONS=(
        "nyc1:New York 1"
        "nyc3:New York 3"
        "sfo3:San Francisco 3"
        "ams3:Amsterdam 3"
        "sgp1:Singapore 1"
        "lon1:London 1"
        "fra1:Frankfurt 1"
        "tor1:Toronto 1"
        "blr1:Bangalore 1"
        "syd1:Sydney 1"
    )
    
    SIZES=(
        "s-1vcpu-1gb:1 vCPU, 1GB RAM ($5/mo)"
        "s-1vcpu-2gb:1 vCPU, 2GB RAM ($10/mo)"
        "s-2vcpu-2gb:2 vCPU, 2GB RAM ($15/mo) - Recommended"
        "s-2vcpu-4gb:2 vCPU, 4GB RAM ($20/mo)"
        "s-4vcpu-8gb:4 vCPU, 8GB RAM ($40/mo)"
    )
    
    IMAGES=(
        "docker-20-04:Docker on Ubuntu 20.04 - Recommended"
        "ubuntu-22-04-x64:Ubuntu 22.04 LTS"
        "debian-11-x64:Debian 11"
    )
    
    # Interactive droplet name entry
    show_header "Create a Droplet"
    echo -e "${GREEN}Create a new droplet${NC}"
    echo -e "${GREEN}Enter a name for your droplet${NC} (default: ${YELLOW}$DEFAULT_NAME${NC}):"
    read -p "> " DROPLET_NAME
    DROPLET_NAME=${DROPLET_NAME:-$DEFAULT_NAME}
    
    # Ask if user wants to use cloud-init
    echo -e "${GREEN}Would you like to use cloud-init for advanced provisioning?${NC} (y/n)"
    read -p "> " USE_CLOUD_INIT
    
    # If using cloud-init, prepare user data
    if [[ $USE_CLOUD_INIT =~ ^[Yy]$ ]]; then
        prepare_cloud_init
        CLOUD_INIT_FILE="$DIR/.cloud-init.yml"
    fi
    
    # Show region selection menu
    REGION_DISPLAY=()
    for region in "${REGIONS[@]}"; do
        REGION_DISPLAY+=("${region//:/ - }")
    done
    select_from_menu "Select a region" "${REGION_DISPLAY[@]}"
    REGION_INDEX=$?
    REGION=$(echo "${REGIONS[$REGION_INDEX]}" | cut -d: -f1)
    
    # Show size selection menu
    SIZE_DISPLAY=()
    for size in "${SIZES[@]}"; do
        SIZE_DISPLAY+=("${size//:/ - }")
    done
    select_from_menu "Select a droplet size" "${SIZE_DISPLAY[@]}"
    SIZE_INDEX=$?
    SIZE=$(echo "${SIZES[$SIZE_INDEX]}" | cut -d: -f1)
    
    # Show image selection menu
    IMAGE_DISPLAY=()
    for image in "${IMAGES[@]}"; do
        IMAGE_DISPLAY+=("${image//:/ - }")
    done
    select_from_menu "Select an image" "${IMAGE_DISPLAY[@]}"
    IMAGE_INDEX=$?
    IMAGE=$(echo "${IMAGES[$IMAGE_INDEX]}" | cut -d: -f1)
    
    # Show selected options and confirm
    show_header "Confirm Droplet Creation"
    echo -e "${GREEN}You selected:${NC}"
    echo -e "  Name:   ${YELLOW}$DROPLET_NAME${NC}"
    echo -e "  Region: ${YELLOW}$REGION${NC} - ${CYAN}$(echo ${REGIONS[$REGION_INDEX]} | cut -d: -f2)${NC}"
    echo -e "  Size:   ${YELLOW}$SIZE${NC} - ${CYAN}$(echo ${SIZES[$SIZE_INDEX]} | cut -d: -f2)${NC}"
    echo -e "  Image:  ${YELLOW}$IMAGE${NC} - ${CYAN}$(echo ${IMAGES[$IMAGE_INDEX]} | cut -d: -f2)${NC}"
    
    if [[ $USE_CLOUD_INIT =~ ^[Yy]$ ]]; then
        echo -e "  Cloud-Init: ${YELLOW}Enabled${NC}"
    else
        echo -e "  Cloud-Init: ${YELLOW}Disabled${NC}"
    fi
    
    echo -e "\n${GREEN}Create this droplet?${NC} (y/n)"
    read -p "> " CONFIRM
    
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Droplet creation cancelled.${NC}"
        return 1
    fi
    
    echo -e "\n${GREEN}Creating droplet: $DROPLET_NAME in $REGION with size $SIZE using image $IMAGE...${NC}"
    
    # Create the droplet using doctl
    if [[ $USE_CLOUD_INIT =~ ^[Yy]$ ]]; then
        doctl compute droplet create $DROPLET_NAME \
            --image $IMAGE \
            --region $REGION \
            --size $SIZE \
            --user-data-file "$CLOUD_INIT_FILE" \
            --wait \
            --ssh-keys $(doctl compute ssh-key list --format ID --no-header | sed 's/$/,/' | tr -d '\n' | sed 's/,$//')
    else
        doctl compute droplet create $DROPLET_NAME \
            --image $IMAGE \
            --region $REGION \
            --size $SIZE \
            --wait \
            --ssh-keys $(doctl compute ssh-key list --format ID --no-header | sed 's/$/,/' | tr -d '\n' | sed 's/,$//')
    fi
    
    # Check if droplet creation was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create droplet. Please try again.${NC}"
        return 1
    fi
    
    # Get the droplet's IP address
    IP=$(doctl compute droplet get $DROPLET_NAME --format PublicIPv4 --no-header)
    
    echo -e "\n${GREEN}Droplet created with IP: ${YELLOW}$IP${NC}"
    echo -e "${GREEN}Waiting for SSH to be available...${NC}"
    
    # Wait for SSH to be available
    ATTEMPTS=0
    MAX_ATTEMPTS=30
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$IP echo 'SSH is up' 2>/dev/null
    do
        echo -e "${YELLOW}Waiting for SSH... (attempt $((++ATTEMPTS))/$MAX_ATTEMPTS)${NC}"
        if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
            echo -e "${RED}Timed out waiting for SSH. Your droplet is created but may not be fully ready.${NC}"
            echo -e "${RED}Try connecting manually later: ssh root@$IP${NC}"
            break
        fi
        sleep 10
    done
    
    # Save droplet info to config
    cat > "$CONFIG_FILE" <<EOF
DROPLET_NAME="$DROPLET_NAME"
DROPLET_IP="$IP"
REGION="$REGION"
SIZE="$SIZE"
IMAGE="$IMAGE"
CREATED_AT="$(date +"%Y-%m-%d %H:%M:%S")"

# Deployment configuration
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-docker-compose}"
WEBSERVER="${WEBSERVER:-nginx}"
DATABASE="${DATABASE:-postgresql}"
APP_PORT="${APP_PORT:-3000}"
API_PORT="${API_PORT:-8000}"
APP_ROOT="${APP_ROOT:-/root/app}"
EOF
    
    # Save variables for current session
    DROPLET_IP="$IP"
    
    echo -e "${GREEN}✓ Droplet created and configuration saved${NC}"
    sleep 2
}

# Function to manage existing droplets
manage_droplet() {
    show_header "Manage Droplet"
    
    # Verify droplet information
    if [ -z "$DROPLET_IP" ]; then
        log_error "No droplet IP found in configuration."
        echo -e "${YELLOW}Please create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    # Check if droplet is actually reachable
    if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "exit" &>/dev/null; then
        log_error "Cannot connect to droplet at $DROPLET_IP"
        echo -e "${RED}The droplet at $DROPLET_IP is not reachable.${NC}"
        echo -e "${YELLOW}Possible issues:${NC}"
        echo -e "  - The droplet has been deleted"
        echo -e "  - The IP address has changed"
        echo -e "  - SSH key issues"
        echo -e "  - Network or firewall issues"
        echo
        echo -e "${YELLOW}Would you like to update the configuration or remove it? (u/r/n)${NC}"
        read -p "> " UPDATE_CONFIG
        
        case $UPDATE_CONFIG in
            [Uu]*)
                echo -e "${GREEN}Enter the new IP address:${NC}"
                read -p "> " NEW_IP
                
                if [[ $NEW_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    DROPLET_IP=$NEW_IP
                    
                    # Update the config file
                    sed -i.bak "s/DROPLET_IP=.*/DROPLET_IP=\"$DROPLET_IP\"/" "$DIR/.do_deploy.conf"
                    echo -e "${GREEN}Configuration updated with new IP: $DROPLET_IP${NC}"
                    sleep 2
                    return 0
                else
                    echo -e "${RED}Invalid IP address format. No changes made.${NC}"
                    sleep 2
                    return 1
                fi
                ;;
            [Rr]*)
                # Remove the config file
                rm -f "$DIR/.do_deploy.conf"
                echo -e "${GREEN}Configuration removed. You can create a new droplet now.${NC}"
                DROPLET_IP=""
                DROPLET_NAME=""
                sleep 2
                return 0
                ;;
            *)
                echo -e "${YELLOW}No changes made.${NC}"
                sleep 2
                return 1
                ;;
        esac
    fi
    
    # Check Docker status if this is a Docker deployment
    DOCKER_STATUS=""
    if [[ "$DEPLOYMENT_TYPE" == "docker"* ]]; then
        if ssh -q -o BatchMode=yes root@$DROPLET_IP "command -v docker" &>/dev/null; then
            DOCKER_STATUS="Installed"
            
            # Check if Docker is running
            if ssh -q -o BatchMode=yes root@$DROPLET_IP "systemctl is-active docker" &>/dev/null; then
                DOCKER_STATUS="Running"
                
                # Check for Docker Compose if this is a docker-compose deployment
                if [[ "$DEPLOYMENT_TYPE" == "docker-compose" ]]; then
                    if ssh -q -o BatchMode=yes root@$DROPLET_IP "command -v docker-compose" &>/dev/null || ssh -q -o BatchMode=yes root@$DROPLET_IP "docker compose version" &>/dev/null; then
                        DOCKER_STATUS="Docker & Compose Running"
                    else
                        DOCKER_STATUS="Docker Running (Compose Not Found)"
                    fi
                fi
            else
                DOCKER_STATUS="Installed (Not Running)"
            fi
        else
            DOCKER_STATUS="Not Installed"
        fi
    fi
    
    # Check for app directory
    APP_DIR_STATUS=""
    if ssh -q -o BatchMode=yes root@$DROPLET_IP "test -d ${APP_ROOT:-/root/app}" &>/dev/null; then
        APP_FILES_COUNT=$(ssh -q -o BatchMode=yes root@$DROPLET_IP "find ${APP_ROOT:-/root/app} -type f | wc -l")
        if [ "$APP_FILES_COUNT" -gt 0 ]; then
            APP_DIR_STATUS="Exists with $APP_FILES_COUNT files"
        else
            APP_DIR_STATUS="Empty"
        fi
    else
        APP_DIR_STATUS="Not Found"
    fi
    
    # Display droplet info
    echo -e "${GREEN}Droplet Information:${NC}"
    echo -e "  Name:     ${YELLOW}$DROPLET_NAME${NC}"
    echo -e "  IP:       ${YELLOW}$DROPLET_IP${NC}"
    echo -e "  Region:   ${YELLOW}$REGION${NC}"
    echo -e "  Size:     ${YELLOW}$SIZE${NC}"
    echo -e "  Created:  ${YELLOW}$CREATED_AT${NC}"
    
    if [ ! -z "$DEPLOYMENT_TYPE" ]; then
        echo -e "  Deploy:   ${YELLOW}$DEPLOYMENT_TYPE${NC}"
    fi
    
    if [ ! -z "$DOCKER_STATUS" ]; then
        echo -e "  Docker:   ${YELLOW}$DOCKER_STATUS${NC}"
    fi
    
    if [ ! -z "$APP_DIR_STATUS" ]; then
        echo -e "  App Dir:  ${YELLOW}$APP_DIR_STATUS${NC}"
    fi
    
    echo
    
    # Menu options
    DROPLET_MENU_OPTIONS=(
        "SSH into droplet"
        "Check server status"
        "Restart services"
        "Power cycle droplet"
        "Remove droplet from config"
        "Delete droplet"
        "Back to main menu"
    )
    
    select_from_menu "Select an action" "${DROPLET_MENU_OPTIONS[@]}"
    DROPLET_CHOICE=$?
    
    case $DROPLET_CHOICE in
        0) # SSH
            clear
            echo -e "${GREEN}Connecting to $DROPLET_NAME ($DROPLET_IP)...${NC}"
            echo -e "${YELLOW}Type 'exit' to return to this menu when done.${NC}"
            echo
            
            ssh root@$DROPLET_IP
            ;;
        1) # Status
            clear
            echo -e "${GREEN}Checking server status...${NC}"
            echo
            
            # Memory and CPU
            echo -e "${CYAN}Memory and CPU:${NC}"
            ssh root@$DROPLET_IP "free -h && echo && top -bn1 | head -n 5"
            echo
            
            # Disk
            echo -e "${CYAN}Disk Usage:${NC}"
            ssh root@$DROPLET_IP "df -h"
            echo
            
            # Service status - check based on deployment type
            echo -e "${CYAN}Service Status:${NC}"
            if [[ "$DEPLOYMENT_TYPE" == "docker"* ]]; then
                ssh root@$DROPLET_IP "systemctl status docker --no-pager | head -n 3"
                echo
                ssh root@$DROPLET_IP "docker ps -a"
            elif [ "$WEBSERVER" == "nginx" ]; then
                ssh root@$DROPLET_IP "systemctl status nginx --no-pager | head -n 3"
            elif [ "$WEBSERVER" == "apache" ]; then
                ssh root@$DROPLET_IP "systemctl status apache2 --no-pager | head -n 3"
            fi
            
            echo
            read -p "Press Enter to continue..."
            ;;
        2) # Restart services
            clear
            echo -e "${GREEN}Select service to restart:${NC}"
            
            SERVICE_OPTIONS=()
            
            # Add docker if it's a docker deployment
            if [[ "$DEPLOYMENT_TYPE" == "docker"* ]]; then
                SERVICE_OPTIONS+=("Docker")
                if [[ "$DEPLOYMENT_TYPE" == "docker-compose" ]]; then
                    SERVICE_OPTIONS+=("Docker Compose")
                fi
            fi
            
            # Add web server if configured
            if [ "$WEBSERVER" == "nginx" ]; then
                SERVICE_OPTIONS+=("Nginx")
            elif [ "$WEBSERVER" == "apache" ]; then
                SERVICE_OPTIONS+=("Apache")
            fi
            
            # Add database if configured
            if [ "$DATABASE" == "postgresql" ]; then
                SERVICE_OPTIONS+=("PostgreSQL")
            elif [ "$DATABASE" == "mysql" ]; then
                SERVICE_OPTIONS+=("MySQL")
            elif [ "$DATABASE" == "mongodb" ]; then
                SERVICE_OPTIONS+=("MongoDB")
            fi
            
            SERVICE_OPTIONS+=("Cancel")
            
            select_from_menu "Select service to restart" "${SERVICE_OPTIONS[@]}"
            SERVICE_CHOICE=$?
            
            if [ $SERVICE_CHOICE -lt $(( ${#SERVICE_OPTIONS[@]} - 1 )) ]; then
                SERVICE=${SERVICE_OPTIONS[$SERVICE_CHOICE]}
                
                echo -e "${YELLOW}Restarting $SERVICE...${NC}"
                
                case $SERVICE in
                    "Docker")
                        ssh root@$DROPLET_IP "systemctl restart docker"
                        ;;
                    "Docker Compose")
                        ssh root@$DROPLET_IP "cd ${APP_ROOT:-/root/app} && docker-compose down && docker-compose up -d"
                        ;;
                    "Nginx")
                        ssh root@$DROPLET_IP "systemctl restart nginx"
                        ;;
                    "Apache")
                        ssh root@$DROPLET_IP "systemctl restart apache2"
                        ;;
                    "PostgreSQL")
                        ssh root@$DROPLET_IP "systemctl restart postgresql"
                        ;;
                    "MySQL")
                        ssh root@$DROPLET_IP "systemctl restart mysql"
                        ;;
                    "MongoDB")
                        ssh root@$DROPLET_IP "systemctl restart mongod"
                        ;;
                esac
                
                echo -e "${GREEN}$SERVICE restarted.${NC}"
                sleep 2
            fi
            ;;
        3) # Power cycle
            clear
            echo -e "${YELLOW}Power options for $DROPLET_NAME ($DROPLET_IP):${NC}"
            
            POWER_OPTIONS=(
                "Reboot droplet"
                "Power Off droplet"
                "Power On droplet"
                "Cancel"
            )
            
            select_from_menu "Select an action" "${POWER_OPTIONS[@]}"
            POWER_CHOICE=$?
            
            case $POWER_CHOICE in
                0) # Reboot
                    echo -e "${YELLOW}Rebooting droplet...${NC}"
                    doctl compute droplet-action reboot $DROPLET_NAME --wait
                    echo -e "${GREEN}Droplet rebooted.${NC}"
                    sleep 2
                    ;;
                1) # Power Off
                    echo -e "${YELLOW}Powering off droplet...${NC}"
                    doctl compute droplet-action power-off $DROPLET_NAME --wait
                    echo -e "${GREEN}Droplet powered off.${NC}"
                    sleep 2
                    ;;
                2) # Power On
                    echo -e "${YELLOW}Powering on droplet...${NC}"
                    doctl compute droplet-action power-on $DROPLET_NAME --wait
                    echo -e "${GREEN}Droplet powered on.${NC}"
                    sleep 2
                    ;;
                3) # Cancel
                    ;;
            esac
            ;;
        4) # Remove from config
            clear
            echo -e "${YELLOW}Remove droplet from configuration?${NC}"
            echo -e "This will only remove the local reference to the droplet."
            echo -e "The droplet itself will continue running on DigitalOcean."
            echo -e "${RED}Are you sure? (y/n)${NC}"
            read -p "> " CONFIRM_REMOVE
            
            if [[ $CONFIRM_REMOVE =~ ^[Yy]$ ]]; then
                rm -f "$DIR/.do_deploy.conf"
                echo -e "${GREEN}Configuration removed.${NC}"
                DROPLET_IP=""
                DROPLET_NAME=""
                sleep 2
                return 0
            fi
            ;;
        5) # Delete droplet
            clear
            echo -e "${RED}!!! WARNING !!!${NC}"
            echo -e "${RED}You are about to delete droplet $DROPLET_NAME ($DROPLET_IP)${NC}"
            echo -e "${RED}This will destroy all data on the droplet and cannot be undone.${NC}"
            echo -e "${RED}Are you ABSOLUTELY sure? (yes/no)${NC}"
            read -p "> " CONFIRM_DELETE
            
            if [ "$CONFIRM_DELETE" == "yes" ]; then
                echo -e "${YELLOW}Deleting droplet...${NC}"
                doctl compute droplet delete $DROPLET_NAME --force
                
                if [ $? -eq 0 ]; then
                    rm -f "$DIR/.do_deploy.conf"
                    echo -e "${GREEN}Droplet deleted and configuration removed.${NC}"
                    DROPLET_IP=""
                    DROPLET_NAME=""
                else
                    echo -e "${RED}Error deleting droplet. Please check manually.${NC}"
                fi
                sleep 2
                return 0
            else
                echo -e "${GREEN}Deletion cancelled.${NC}"
                sleep 2
            fi
            ;;
        6) # Back
            return 0
            ;;
    esac
    
    # Return to the manage_droplet menu after action completes
    manage_droplet
}