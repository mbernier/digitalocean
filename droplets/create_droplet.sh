#!/bin/bash
# Create a Docker-ready droplet on DigitalOcean with interactive menu selection

# ANSI color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color
HIGHLIGHT='\033[7m' # Reverse video for highlight

# Print header
clear
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  DigitalOcean Droplet Creator     ${NC}"
echo -e "${BLUE}====================================${NC}"

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
    echo -e "${RED}Error: doctl is not installed.${NC}"
    echo -e "Please install the DigitalOcean CLI tool first:"
    echo -e "${YELLOW}  brew install doctl  # On macOS${NC}"
    echo -e "${YELLOW}  apt install doctl   # On Ubuntu/Debian${NC}"
    exit 1
fi

# Check authentication with DigitalOcean
echo -e "${GREEN}Checking if authenticated with DigitalOcean...${NC}"
if ! doctl account get &> /dev/null; then
    echo -e "${YELLOW}Not authenticated. Let's set up authentication now.${NC}"
    echo -e "You will need to create a personal access token at:"
    echo -e "${CYAN}https://cloud.digitalocean.com/account/api/tokens${NC}"
    echo -e "With read and write permissions."
    echo
    doctl auth init
    
    # Check if auth was successful
    if ! doctl account get &> /dev/null; then
        echo -e "${RED}Authentication failed. Please try again later.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Authenticated with DigitalOcean! Now let's create your droplet!${NC}"
echo

# Default values
DEFAULT_NAME="droplet-$(date +%Y%m%d)"
DROPLET_NAME=""

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

# Default indices
DEFAULT_REGION_INDEX=0
DEFAULT_SIZE_INDEX=2
DEFAULT_IMAGE_INDEX=0

# Function to display a menu and return the selected index
select_from_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local max=$((${#options[@]} - 1))
    
    tput civis # Hide cursor
    
    while true; do
        clear
        echo -e "${BLUE}====================================${NC}"
        echo -e "${BLUE}  DigitalOcean Droplet Creator     ${NC}"
        echo -e "${BLUE}====================================${NC}"
        echo -e "${GREEN}$title${NC} (use arrow keys and Enter to select)"
        echo
        
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e " ${HIGHLIGHT}→ ${options[$i]}${NC}"
            else
                echo -e "   ${options[$i]}"
            fi
        done
        
        read -rsn3 key
        
        case "$key" in
            $'\e[A') # Up arrow
                if [ $selected -gt 0 ]; then
                    selected=$((selected - 1))
                else
                    selected=$max
                fi
                ;;
            $'\e[B') # Down arrow
                if [ $selected -lt $max ]; then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;
            "") # Enter key
                tput cnorm # Show cursor again
                return $selected
                ;;
        esac
    done
}

# Function to process array options
get_option_value() {
    local array=("$@")
    local index="$1"
    local option="${array[$index]}"
    
    echo "${option%%:*}" # Return everything before the colon
}

# Check if SSH keys are set up
echo -e "${GREEN}Checking for SSH keys in your DigitalOcean account...${NC}"
SSH_KEYS=$(doctl compute ssh-key list --format ID --no-header | wc -l)
if [ "$SSH_KEYS" -eq 0 ]; then
    echo -e "${YELLOW}No SSH keys found in your DigitalOcean account.${NC}"
    echo -e "You need to add an SSH key to access your droplet."
    echo -e "Would you like to add your default SSH key (~/.ssh/id_rsa.pub)? (y/n)"
    read -p "> " ADD_KEY
    
    if [[ $ADD_KEY =~ ^[Yy]$ ]]; then
        if [ ! -f ~/.ssh/id_rsa.pub ]; then
            echo -e "${RED}SSH key not found. Please generate one first:${NC}"
            echo -e "${YELLOW}  ssh-keygen -t rsa${NC}"
            exit 1
        fi
        
        KEY_NAME="key-$(date +%Y%m%d)"
        echo -e "Adding SSH key as: $KEY_NAME"
        doctl compute ssh-key import "$KEY_NAME" --public-key-file ~/.ssh/id_rsa.pub
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to add SSH key. Please add it manually.${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}SSH key added successfully!${NC}"
    else
        echo -e "${RED}Cannot continue without SSH keys. Please add them manually:${NC}"
        echo -e "${YELLOW}doctl compute ssh-key import your-key-name --public-key-file ~/.ssh/id_rsa.pub${NC}"
        exit 1
    fi
fi

# Interactive droplet name entry
clear
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  DigitalOcean Droplet Creator     ${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "${GREEN}Enter a name for your droplet${NC} (default: ${YELLOW}$DEFAULT_NAME${NC}):"
read -p "> " DROPLET_NAME
DROPLET_NAME=${DROPLET_NAME:-$DEFAULT_NAME}

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
clear
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  DigitalOcean Droplet Creator     ${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "${GREEN}You selected:${NC}"
echo -e "  Name:   ${YELLOW}$DROPLET_NAME${NC}"
echo -e "  Region: ${YELLOW}$REGION${NC} - ${CYAN}$(echo ${REGIONS[$REGION_INDEX]} | cut -d: -f2)${NC}"
echo -e "  Size:   ${YELLOW}$SIZE${NC} - ${CYAN}$(echo ${SIZES[$SIZE_INDEX]} | cut -d: -f2)${NC}"
echo -e "  Image:  ${YELLOW}$IMAGE${NC} - ${CYAN}$(echo ${IMAGES[$IMAGE_INDEX]} | cut -d: -f2)${NC}"
echo -e "\n${GREEN}Create this droplet?${NC} (y/n)"
read -p "> " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Droplet creation cancelled.${NC}"
    exit 0
fi

echo -e "\n${GREEN}Creating droplet: $DROPLET_NAME in $REGION with size $SIZE using image $IMAGE...${NC}"

# Create the droplet using doctl
doctl compute droplet create $DROPLET_NAME \
    --image $IMAGE \
    --region $REGION \
    --size $SIZE \
    --wait \
    --ssh-keys $(doctl compute ssh-key list --format ID --no-header | sed 's/$/,/' | tr -d '\n' | sed 's/,$//')

# Check if droplet creation was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create droplet. Please try again.${NC}"
    exit 1
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

# Create a .env.production file with the droplet IP
cat > .env.production <<EOF
DROPLET_IP=$IP
DROPLET_NAME=$DROPLET_NAME
REGION=$REGION
SIZE=$SIZE
IMAGE=$IMAGE
CREATED_AT=$(date +"%Y-%m-%d %H:%M:%S")
EOF

echo -e "\n${GREEN}Droplet is ready!${NC}"
echo -e "  IP Address: ${YELLOW}$IP${NC}"
echo -e "  SSH Command: ${YELLOW}ssh root@$IP${NC}"
echo -e "  Docker Host: ${YELLOW}export DOCKER_HOST=ssh://root@$IP${NC}"
echo -e "${GREEN}Created .env.production with droplet information${NC}"
echo -e "\n${GREEN}Next steps:${NC}"
echo -e "  1. ${YELLOW}./scripts/do/setup_domain.sh${NC} - Configure your domain"
echo -e "  2. ${YELLOW}./scripts/do/deploy.sh${NC} - Deploy your application"
echo -e "  3. ${YELLOW}./scripts/do/data_migrate.sh${NC} - Migrate your data"
