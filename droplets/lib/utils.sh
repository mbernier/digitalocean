#!/bin/bash
# Utility functions for the DigitalOcean deployment script

# ANSI color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color
HIGHLIGHT='\033[7m' # Reverse video for highlight

# Print a header with a title
show_header() {
    local title="$1"
    clear
    echo -e "${BLUE}====================================${NC}"
    echo -e "${BLUE}  $title     ${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo
}

# Show the welcome screen
show_welcome() {
    show_header "DigitalOcean Deployment Wizard"
    echo -e "${GREEN}Welcome to the DigitalOcean Deployment Wizard!${NC}"
    echo -e "This tool will help you deploy your application to DigitalOcean."
    echo -e "You'll be guided through the process step by step."
    echo
    echo -e "Press ${YELLOW}Enter${NC} to continue..."
    read
}

# Function to display a menu and return the selected index
select_from_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local max=$((${#options[@]} - 1))
    
    tput civis # Hide cursor
    
    while true; do
        show_header "DigitalOcean Deployment Wizard"
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

# Initial setup wizard for project configuration
initial_setup_wizard() {
    show_header "Project Setup"
    echo -e "${GREEN}Let's configure your project settings.${NC}"
    echo
    
    # Project name
    echo -e "Enter a name for your project:"
    read -p "> " PROJECT_NAME
    
    # Deployment type
    DEPLOYMENT_OPTIONS=(
        "Docker Compose (multiple containers)"
        "Single Docker Container"
        "Traditional (non-Docker)"
        "Static Website"
    )
    
    select_from_menu "Select your deployment type" "${DEPLOYMENT_OPTIONS[@]}"
    DEPLOYMENT_TYPE_INDEX=$?
    
    case $DEPLOYMENT_TYPE_INDEX in
        0) DEPLOYMENT_TYPE="docker-compose" ;;
        1) DEPLOYMENT_TYPE="docker" ;;
        2) DEPLOYMENT_TYPE="traditional" ;;
        3) DEPLOYMENT_TYPE="static" ;;
    esac
    
    # Web server
    WEBSERVER_OPTIONS=(
        "Nginx (recommended)"
        "Apache"
        "None (direct container exposure)"
    )
    
    select_from_menu "Select your web server" "${WEBSERVER_OPTIONS[@]}"
    WEBSERVER_INDEX=$?
    
    case $WEBSERVER_INDEX in
        0) WEBSERVER="nginx" ;;
        1) WEBSERVER="apache" ;;
        2) WEBSERVER="none" ;;
    esac
    
    # Database
    DATABASE_OPTIONS=(
        "PostgreSQL"
        "MySQL"
        "MongoDB"
        "None"
    )
    
    select_from_menu "Select your database" "${DATABASE_OPTIONS[@]}"
    DATABASE_INDEX=$?
    
    case $DATABASE_INDEX in
        0) DATABASE="postgresql" ;;
        1) DATABASE="mysql" ;;
        2) DATABASE="mongodb" ;;
        3) DATABASE="none" ;;
    esac
    
    # Save project configuration
    cat > "$DIR/.do_deploy.project" <<EOF
PROJECT_NAME="$PROJECT_NAME"
DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE"
WEBSERVER="$WEBSERVER"
DATABASE="$DATABASE"
EOF
    
    echo -e "${GREEN}Project configuration saved.${NC}"
    sleep 1
}

# Project settings menu
project_settings_menu() {
    while true; do
        show_header "Project Settings"
        
        echo -e "${GREEN}Current Project Settings:${NC}"
        echo -e "  Project Name: ${YELLOW}$PROJECT_NAME${NC}"
        echo -e "  Deployment Type: ${YELLOW}$DEPLOYMENT_TYPE${NC}"
        echo -e "  Web Server: ${YELLOW}$WEBSERVER${NC}"
        echo -e "  Database: ${YELLOW}$DATABASE${NC}"
        echo
        
        SETTINGS_OPTIONS=(
            "Change Project Name"
            "Change Deployment Type"
            "Change Web Server"
            "Change Database"
            "Back to Main Menu"
        )
        
        select_from_menu "Select a setting to change" "${SETTINGS_OPTIONS[@]}"
        SETTING_CHOICE=$?
        
        case $SETTING_CHOICE in
            0)
                echo -e "Enter new project name:"
                read -p "> " PROJECT_NAME
                ;;
            1)
                DEPLOYMENT_OPTIONS=(
                    "Docker Compose (multiple containers)"
                    "Single Docker Container"
                    "Traditional (non-Docker)"
                    "Static Website"
                )
                
                select_from_menu "Select your deployment type" "${DEPLOYMENT_OPTIONS[@]}"
                DEPLOYMENT_TYPE_INDEX=$?
                
                case $DEPLOYMENT_TYPE_INDEX in
                    0) DEPLOYMENT_TYPE="docker-compose" ;;
                    1) DEPLOYMENT_TYPE="docker" ;;
                    2) DEPLOYMENT_TYPE="traditional" ;;
                    3) DEPLOYMENT_TYPE="static" ;;
                esac
                ;;
            2)
                WEBSERVER_OPTIONS=(
                    "Nginx (recommended)"
                    "Apache"
                    "None (direct container exposure)"
                )
                
                select_from_menu "Select your web server" "${WEBSERVER_OPTIONS[@]}"
                WEBSERVER_INDEX=$?
                
                case $WEBSERVER_INDEX in
                    0) WEBSERVER="nginx" ;;
                    1) WEBSERVER="apache" ;;
                    2) WEBSERVER="none" ;;
                esac
                ;;
            3)
                DATABASE_OPTIONS=(
                    "PostgreSQL"
                    "MySQL"
                    "MongoDB"
                    "None"
                )
                
                select_from_menu "Select your database" "${DATABASE_OPTIONS[@]}"
                DATABASE_INDEX=$?
                
                case $DATABASE_INDEX in
                    0) DATABASE="postgresql" ;;
                    1) DATABASE="mysql" ;;
                    2) DATABASE="mongodb" ;;
                    3) DATABASE="none" ;;
                esac
                ;;
            4)
                # Save changes before returning
                cat > "$DIR/.do_deploy.project" <<EOF
PROJECT_NAME="$PROJECT_NAME"
DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE"
WEBSERVER="$WEBSERVER"
DATABASE="$DATABASE"
EOF
                return
                ;;
        esac
        
        # Save changes after each modification
        cat > "$DIR/.do_deploy.project" <<EOF
PROJECT_NAME="$PROJECT_NAME"
DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE"
WEBSERVER="$WEBSERVER"
DATABASE="$DATABASE"
EOF
        
        echo -e "${GREEN}Settings updated.${NC}"
        sleep 1
    done
}

# Check prerequisites
check_prerequisites() {
    show_header "Checking Prerequisites"
    echo -e "${GREEN}Checking prerequisites...${NC}"
    
    if ! command -v doctl &> /dev/null; then
        echo -e "${RED}Error: doctl is not installed.${NC}"
        echo -e "Please install the DigitalOcean CLI tool first:"
        echo -e "${YELLOW}  brew install doctl  # On macOS${NC}"
        echo -e "${YELLOW}  apt install doctl   # On Ubuntu/Debian${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ doctl is installed${NC}"
    sleep 1
}

# Check authentication with DigitalOcean
check_auth() {
    show_header "Checking Authentication"
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
    
    echo -e "${GREEN}✓ Authenticated with DigitalOcean!${NC}"
    sleep 1
}

# Check if SSH keys are set up
check_ssh_keys() {
    show_header "Checking SSH Keys"
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
    
    echo -e "${GREEN}✓ SSH keys are set up${NC}"
    sleep 1
}
