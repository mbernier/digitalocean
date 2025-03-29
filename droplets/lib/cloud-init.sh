#!/bin/bash
# Cloud-init provisioning functions

# Prepare cloud-init configuration
prepare_cloud_init() {
    show_header "Cloud-Init Configuration"
    echo -e "${GREEN}Configure cloud-init for initial server setup${NC}"
    echo -e "Cloud-init allows automatic provisioning when your droplet is created."
    echo
    
    # Create a temp file to build the cloud-init config
    CLOUD_INIT_FILE="$DIR/.cloud-init.yml"
    
    # Start with the basic cloud-init structure
    cat > "$CLOUD_INIT_FILE" <<EOF
#cloud-config
package_update: true
package_upgrade: true

timezone: UTC

packages:
  - curl
  - wget
  - vim
  - htop
  - git
  - unzip
EOF
    
    # Ask about additional packages
    echo -e "${GREEN}Enter additional packages to install (space-separated):${NC}"
    read -p "> " ADDITIONAL_PACKAGES
    
    if [ ! -z "$ADDITIONAL_PACKAGES" ]; then
        for pkg in $ADDITIONAL_PACKAGES; do
            echo "  - $pkg" >> "$CLOUD_INIT_FILE"
        done
    fi
    
    # Ask about users
    echo -e "\n${GREEN}Do you want to create additional users?${NC} (y/n)"
    read -p "> " CREATE_USERS
    
    if [[ $CREATE_USERS =~ ^[Yy]$ ]]; then
        echo -e "How many users do you want to create?"
        read -p "> " NUM_USERS
        
        echo -e "\nusers:" >> "$CLOUD_INIT_FILE"
        
        for (( i=1; i<=$NUM_USERS; i++ )); do
            echo -e "\nUser $i:"
            echo -e "  Username:"
            read -p "> " USERNAME
            
            echo -e "  Should this user have sudo access? (y/n)"
            read -p "> " SUDO_ACCESS
            
            if [[ $SUDO_ACCESS =~ ^[Yy]$ ]]; then
                SUDO_GROUPS="sudo"
            else
                SUDO_GROUPS=""
            fi
            
            cat >> "$CLOUD_INIT_FILE" <<EOF
  - name: $USERNAME
    groups: [adm, $SUDO_GROUPS]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
EOF
            echo -e "  Enter path to SSH public key for this user (or leave empty to skip):"
            read -p "> " SSH_KEY_PATH
            
            if [ ! -z "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
                echo "      - $(cat $SSH_KEY_PATH)" >> "$CLOUD_INIT_FILE"
            fi
        done
    fi
    
    # Ask about firewalls
    echo -e "\n${GREEN}Do you want to configure a basic firewall?${NC} (y/n)"
    read -p "> " CONFIGURE_FIREWALL
    
    if [[ $CONFIGURE_FIREWALL =~ ^[Yy]$ ]]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF

runcmd:
  - |
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
EOF
        
        echo -e "  Enter additional ports to open (e.g., 8080 3000 5432):"
        read -p "> " ADDITIONAL_PORTS
        
        if [ ! -z "$ADDITIONAL_PORTS" ]; then
            for port in $ADDITIONAL_PORTS; do
                echo "    ufw allow $port/tcp" >> "$CLOUD_INIT_FILE"
            done
        fi
        
        echo "    ufw --force enable" >> "$CLOUD_INIT_FILE"
    else
        # Start runcmd section if it doesn't exist yet
        echo -e "\nruncmd:" >> "$CLOUD_INIT_FILE"
    fi
    
    # Docker setup
    if [ "$DEPLOYMENT_TYPE" == "docker" ] || [ "$DEPLOYMENT_TYPE" == "docker-compose" ]; then
        echo -e "\n${GREEN}Setting up Docker in cloud-init...${NC}"
        
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker root
EOF
        
        if [ "$DEPLOYMENT_TYPE" == "docker-compose" ]; then
            cat >> "$CLOUD_INIT_FILE" <<EOF
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
EOF
        fi
    fi
    
    # Database setup
    if [ "$DATABASE" == "postgresql" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    apt-get install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
EOF
    elif [ "$DATABASE" == "mysql" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password temp_password'
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password temp_password'
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
EOF
    elif [ "$DATABASE" == "mongodb" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org
    systemctl enable mongod
    systemctl start mongod
EOF
    fi
    
    # Web server setup
    if [ "$WEBSERVER" == "nginx" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
EOF
    elif [ "$WEBSERVER" == "apache" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    apt-get install -y apache2
    systemctl enable apache2
    systemctl start apache2
EOF
    fi
    
    # Add certbot for SSL if a web server is selected
    if [ "$WEBSERVER" == "nginx" ] || [ "$WEBSERVER" == "apache" ]; then
        cat >> "$CLOUD_INIT_FILE" <<EOF
  - |
    apt-get install -y certbot
EOF
        
        if [ "$WEBSERVER" == "nginx" ]; then
            echo "    apt-get install -y python3-certbot-nginx" >> "$CLOUD_INIT_FILE"
        elif [ "$WEBSERVER" == "apache" ]; then
            echo "    apt-get install -y python3-certbot-apache" >> "$CLOUD_INIT_FILE"
        fi
    fi
    
    # Custom scripts
    echo -e "\n${GREEN}Do you want to add custom initialization scripts?${NC} (y/n)"
    read -p "> " ADD_CUSTOM_SCRIPTS
    
    if [[ $ADD_CUSTOM_SCRIPTS =~ ^[Yy]$ ]]; then
        echo -e "Enter the path to your custom script:"
        read -p "> " CUSTOM_SCRIPT_PATH
        
        if [ -f "$CUSTOM_SCRIPT_PATH" ]; then
            echo -e "\nwrite_files:" >> "$CLOUD_INIT_FILE"
            echo "  - path: /root/custom_init.sh" >> "$CLOUD_INIT_FILE"
            echo "    permissions: '0755'" >> "$CLOUD_INIT_FILE"
            echo "    content: |" >> "$CLOUD_INIT_FILE"
            
            while IFS= read -r line; do
                echo "      $line" >> "$CLOUD_INIT_FILE"
            done < "$CUSTOM_SCRIPT_PATH"
            
            # Add to runcmd to execute the script
            echo "  - /root/custom_init.sh" >> "$CLOUD_INIT_FILE"
        else
            echo -e "${RED}Custom script file not found.${NC}"
        fi
    fi
    
    echo -e "${GREEN}Cloud-init configuration prepared.${NC}"
}

# Cloud-init menu for advanced options
cloud_init_menu() {
    if [ -z "$DROPLET_IP" ]; then
        show_header "Cloud-Init Menu"
        echo -e "${RED}No droplet found. Create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    while true; do
        show_header "Cloud-Init Menu"
        
        CLOUD_INIT_OPTIONS=(
            "Install additional packages"
            "Create additional users"
            "Configure firewall rules"
            "Run custom provisioning scripts"
            "Back to main menu"
        )
        
        select_from_menu "Select an action" "${CLOUD_INIT_OPTIONS[@]}"
        CLOUD_INIT_CHOICE=$?
        
        case $CLOUD_INIT_CHOICE in
            0)
                show_header "Install Packages"
                echo -e "${GREEN}Enter packages to install (space-separated):${NC}"
                read -p "> " PACKAGES
                
                if [ ! -z "$PACKAGES" ]; then
                    export DOCKER_HOST=ssh://root@$DROPLET_IP
                    ssh root@$DROPLET_IP "apt-get update && apt-get install -y $PACKAGES"
                    unset DOCKER_HOST
                    
                    echo -e "${GREEN}Packages installed.${NC}"
                    sleep 1
                fi
                ;;
            1)
                show_header "Create Users"
                echo -e "${GREEN}Enter username:${NC}"
                read -p "> " NEW_USER
                
                if [ ! -z "$NEW_USER" ]; then
                    echo -e "${GREEN}Should this user have sudo access? (y/n)${NC}"
                    read -p "> " SUDO_ACCESS
                    
                    SUDO_GROUP=""
                    if [[ $SUDO_ACCESS =~ ^[Yy]$ ]]; then
                        SUDO_GROUP="-G sudo"
                    fi
                    
                    ssh root@$DROPLET_IP "useradd -m -s /bin/bash $SUDO_GROUP $NEW_USER"
                    
                    echo -e "${GREEN}Do you want to add an SSH key for this user? (y/n)${NC}"
                    read -p "> " ADD_SSH_KEY
                    
                    if [[ $ADD_SSH_KEY =~ ^[Yy]$ ]]; then
                        echo -e "${GREEN}Enter path to SSH public key:${NC}"
                        read -p "> " SSH_KEY_PATH
                        
                        if [ -f "$SSH_KEY_PATH" ]; then
                            ssh root@$DROPLET_IP "mkdir -p /home/$NEW_USER/.ssh"
                            cat "$SSH_KEY_PATH" | ssh root@$DROPLET_IP "cat >> /home/$NEW_USER/.ssh/authorized_keys"
                            ssh root@$DROPLET_IP "chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh && chmod 700 /home/$NEW_USER/.ssh && chmod 600 /home/$NEW_USER/.ssh/authorized_keys"
                        else
                            echo -e "${RED}SSH key file not found.${NC}"
                        fi
                    fi
                    
                    echo -e "${GREEN}User created.${NC}"
                    sleep 1
                fi
                ;;
            2)
                show_header "Configure Firewall"
                echo -e "${GREEN}Enter ports to open (space-separated):${NC}"
                read -p "> " PORTS
                
                if [ ! -z "$PORTS" ]; then
                    ssh root@$DROPLET_IP "apt-get install -y ufw"
                    
                    for port in $PORTS; do
                        ssh root@$DROPLET_IP "ufw allow $port/tcp"
                    done
                    
                    # Make sure SSH is allowed
                    ssh root@$DROPLET_IP "ufw allow 22/tcp"
                    
                    echo -e "${GREEN}Enable the firewall? (y/n)${NC}"
                    read -p "> " ENABLE_FIREWALL
                    
                    if [[ $ENABLE_FIREWALL =~ ^[Yy]$ ]]; then
                        ssh root@$DROPLET_IP "ufw --force enable"
                    fi
                    
                    echo -e "${GREEN}Firewall configured.${NC}"
                    sleep 1
                fi
                ;;
            3)
                show_header "Custom Scripts"
                echo -e "${GREEN}Enter path to custom script:${NC}"
                read -p "> " SCRIPT_PATH
                
                if [ -f "$SCRIPT_PATH" ]; then
                    scp "$SCRIPT_PATH" root@$DROPLET_IP:/root/custom_script.sh
                    ssh root@$DROPLET_IP "chmod +x /root/custom_script.sh && /root/custom_script.sh"
                    
                    echo -e "${GREEN}Script executed.${NC}"
                    sleep 1
                else
                    echo -e "${RED}Script file not found.${NC}"
                    sleep 1
                fi
                ;;
            4)
                return 0
                ;;
        esac
    done
}
