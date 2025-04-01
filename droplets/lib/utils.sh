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

# Configure preferred editor
PREFERRED_EDITOR="nano"
EDITOR_INSTRUCTIONS="Use arrow keys to navigate, CTRL+O to save, CTRL+X to exit"

# Function to safely edit files via SSH
ssh_edit_file() {
    local host="$1"
    local file_path="$2"
    local temp_file="/tmp/do_deploy_temp_$(date +%s).txt"
    
    # Instead of editing directly on the server, download the file, edit locally, then upload
    echo -e "${GREEN}Downloading file for editing...${NC}"
    scp "$host:$file_path" "$temp_file" 2>/dev/null
    
    if [ ! -f "$temp_file" ]; then
        # File doesn't exist on server, create an empty one
        touch "$temp_file"
    fi
    
    # Provide clear instructions for editing
    echo -e "${YELLOW}===========================================${NC}"
    echo -e "${YELLOW}   FILE EDITOR - PLEASE READ CAREFULLY   ${NC}"
    echo -e "${YELLOW}===========================================${NC}"
    echo -e "${GREEN}1. The file will open in your default text editor.${NC}"
    echo -e "${GREEN}2. Make your changes and save the file.${NC}"
    echo -e "${GREEN}3. Close the editor to continue the deployment.${NC}"
    echo -e "${YELLOW}===========================================${NC}"
    echo -e "Press ${CYAN}Enter${NC} to open the editor..."
    read
    
    # Open the file with the user's default editor or fallback to nano
    if [ -n "$EDITOR" ]; then
        $EDITOR "$temp_file"
    else
        nano "$temp_file"
    fi
    
    # Ask for confirmation before uploading
    echo -e "${GREEN}Upload the edited file to the server? (y/n)${NC}"
    read -p "> " UPLOAD_CONFIRM
    
    if [[ $UPLOAD_CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Uploading file to server...${NC}"
        scp "$temp_file" "$host:$file_path"
        echo -e "${GREEN}File uploaded successfully.${NC}"
    else
        echo -e "${YELLOW}Changes not uploaded. Continuing...${NC}"
    fi
    
    # Clean up
    rm -f "$temp_file"
}

# Function to safely edit local files
edit_local_file() {
    local file_path="$1"
    
    echo -e "${YELLOW}Editor tips: This will open ${PREFERRED_EDITOR}. ${EDITOR_INSTRUCTIONS}.${NC}"
    echo -e "${YELLOW}If you see strange characters when using arrow keys, try pressing ESC first.${NC}"
    
    # Force the use of nano to avoid terminal issues
    EDITOR=${PREFERRED_EDITOR} ${PREFERRED_EDITOR} "${file_path}"
}

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

# Function to select programming languages and suggest appropriate packages
language_packages_menu() {
    show_header "Programming Languages"
    echo -e "${GREEN}Select the programming languages used in your project${NC}"
    echo -e "${YELLOW}This will help suggest appropriate packages to install${NC}"
    echo
    
    # Array to hold selected languages
    SELECTED_LANGS=""
    
    # Define language options and their packages
    # We'll use simple arrays instead of associative arrays for compatibility
    LANGUAGES=("Python" "Node.js" "Ruby" "PHP" "Go" "Java")
    
    # Function to get packages for a language
    get_packages_for_language() {
        local lang="$1"
        case "$lang" in
            "Python")
                echo "python3-pip python3-venv build-essential libpq-dev"
                ;;
            "Node.js")
                echo "nodejs npm"
                ;;
            "Ruby")
                echo "ruby-full build-essential zlib1g-dev"
                ;;
            "PHP")
                echo "php php-cli php-fpm php-json php-common php-mysql php-zip php-gd php-mbstring php-curl php-xml php-pear php-bcmath"
                ;;
            "Go")
                echo "golang-go"
                ;;
            "Java")
                echo "default-jdk maven"
                ;;
            *)
                echo ""
                ;;
        esac
    }
    
    # Create menu options
    LANGUAGE_OPTIONS=()
    for lang in "${LANGUAGES[@]}"; do
        LANGUAGE_OPTIONS+=("$lang")
    done
    LANGUAGE_OPTIONS+=("Done selecting")
    
    # Keep asking until user selects "Done"
    while true; do
        select_from_menu "Select a language (or Done when finished)" "${LANGUAGE_OPTIONS[@]}"
        LANG_CHOICE=$?
        
        # If user selected "Done", break the loop
        if [ "${LANGUAGE_OPTIONS[$LANG_CHOICE]}" == "Done selecting" ]; then
            break
        fi
        
        # Add selected language to string if not already selected
        selected_lang="${LANGUAGE_OPTIONS[$LANG_CHOICE]}"
        if [[ ! "$SELECTED_LANGS" =~ "$selected_lang" ]]; then
            if [ -z "$SELECTED_LANGS" ]; then
                SELECTED_LANGS="$selected_lang"
            else
                SELECTED_LANGS="$SELECTED_LANGS $selected_lang"
            fi
            echo -e "${GREEN}Added ${selected_lang} to selected languages${NC}"
            sleep 1
        else
            echo -e "${YELLOW}${selected_lang} already selected${NC}"
            sleep 1
        fi
    done
    
    # Generate package suggestions based on selected languages
    SUGGESTED_PACKAGES="git curl wget"  # Base packages everyone needs
    
    for lang in $SELECTED_LANGS; do
        lang_packages=$(get_packages_for_language "$lang")
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES $lang_packages"
    done
    
    # Load existing project config if available
    PROJECT_CONFIG="$DIR/.do_deploy.project"
    PROJECT_NAME=${PROJECT_NAME:-"MyProject"}
    DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-"docker-compose"}
    WEBSERVER=${WEBSERVER:-"nginx"}
    DATABASE=${DATABASE:-"postgresql"}
    
    if [ -f "$PROJECT_CONFIG" ]; then
        log_verbose "Reading existing project configuration"
        source "$PROJECT_CONFIG"
    fi
    
    # Add database-specific packages if needed
    if [ "$DATABASE" == "postgresql" ]; then
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES postgresql-client"
    elif [ "$DATABASE" == "mysql" ]; then
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES mysql-client"
    elif [ "$DATABASE" == "mongodb" ]; then
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES mongodb-clients"
    fi
    
    # Add web server specific packages if needed
    if [ "$WEBSERVER" == "nginx" ]; then
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES certbot python3-certbot-nginx"
    elif [ "$WEBSERVER" == "apache" ]; then
        SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES certbot python3-certbot-apache"
    fi
    
    # Create or update the project config file
    if [ -f "$PROJECT_CONFIG" ]; then
        # Update existing file without using sed -i for Mac compatibility
        grep -v 'SELECTED_LANGUAGES=' "$PROJECT_CONFIG" > "$PROJECT_CONFIG.tmp"
        grep -v 'SUGGESTED_PACKAGES=' "$PROJECT_CONFIG.tmp" > "$PROJECT_CONFIG"
        echo "SELECTED_LANGUAGES=\"$SELECTED_LANGS\"" >> "$PROJECT_CONFIG"
        echo "SUGGESTED_PACKAGES=\"$SUGGESTED_PACKAGES\"" >> "$PROJECT_CONFIG"
        rm -f "$PROJECT_CONFIG.tmp"
    else
        # Create new file
        mkdir -p "$DIR"
        cat > "$PROJECT_CONFIG" <<EOF
PROJECT_NAME="$PROJECT_NAME"
DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE" 
WEBSERVER="$WEBSERVER"
DATABASE="$DATABASE"
SELECTED_LANGUAGES="$SELECTED_LANGS"
SUGGESTED_PACKAGES="$SUGGESTED_PACKAGES"
EOF
    fi
    
    echo -e "${GREEN}Based on your selections, we recommend installing:${NC}"
    echo -e "${YELLOW}$SUGGESTED_PACKAGES${NC}"
    echo
    echo -e "You can edit this list when prompted during the droplet creation process."
    echo
    read -p "Press Enter to continue..."
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
    
    # Get languages and suggested packages
    language_packages_menu
    
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