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
EOF
    
    # Save variables for current session
    DROPLET_IP="$IP"
    
    echo -e "${GREEN}✓ Droplet created and configuration saved${NC}"
    sleep 2
}
