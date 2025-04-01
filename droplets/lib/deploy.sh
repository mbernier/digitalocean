#!/bin/bash
# Deployment functions

# Deploy the application
deploy_app() {
    show_header "Deploy Application"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        log_error "No droplet IP found. Please create a droplet first."
        echo -e "${YELLOW}To create a droplet:${NC}"
        echo -e "  1. Return to the main menu"
        echo -e "  2. Select 'Create a new droplet'"
        echo -e "  3. Follow the prompts to configure and create your droplet"
        echo -e "  4. Wait for droplet initialization to complete"
        echo -e "  5. Return to this menu option"
        
        read -p "Press Enter to return to the main menu..."
        return 1
    fi
    
    log_verbose "Found droplet IP: $DROPLET_IP"
    
    # Verify SSH connection
    log_verbose "Verifying SSH connection to $DROPLET_IP..."
    if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP exit &>/dev/null; then
        log_error "Cannot connect to the droplet at $DROPLET_IP"
        echo -e "${YELLOW}Possible issues:${NC}"
        echo -e "  - SSH key not configured correctly"
        echo -e "  - Droplet not fully initialized yet (try again in a minute)"
        echo -e "  - Firewall blocking SSH connections"
        echo -e "  - Incorrect IP address: $DROPLET_IP"
        
        read -p "Press Enter to return to the main menu..."
        return 1
    fi
    
    log_verbose "SSH connection verified successfully"
    
    # Check if app is already deployed
    log_verbose "Checking if application is already deployed..."
    APP_DEPLOYED=false
    if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "test -d ${APP_ROOT:-/root/app} && ls -A ${APP_ROOT:-/root/app} | grep -q ." &>/dev/null; then
        log_verbose "Detected existing deployment in ${APP_ROOT:-/root/app}"
        APP_DEPLOYED=true
        
        echo -e "${YELLOW}An existing deployment was detected.${NC} What would you like to do?"
        DEPLOY_OPTIONS=(
            "Update existing deployment"
            "Replace with fresh deployment"
            "Return to main menu"
        )
        
        select_from_menu "Select an option" "${DEPLOY_OPTIONS[@]}"
        DEPLOY_CHOICE=$?
        
        case $DEPLOY_CHOICE in
            0) # Update
                log_verbose "Updating existing deployment..."
                # Continue with deployment but skip environment setup if .env exists
                if ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP "test -f ${APP_ROOT:-/root/app}/.env" &>/dev/null; then
                    log_verbose "Existing .env file found, will skip environment setup unless explicitly requested"
                    SKIP_ENV_SETUP=true
                fi
                ;;
            1) # Replace
                log_verbose "Replacing with fresh deployment..."
                echo -e "${YELLOW}This will remove all existing deployment files. Proceed?${NC} (y/n)"
                read -p "> " CONFIRM_REPLACE
                
                if [[ $CONFIRM_REPLACE =~ ^[Yy]$ ]]; then
                    log_verbose "Removing existing deployment..."
                    ssh root@$DROPLET_IP "rm -rf ${APP_ROOT:-/root/app}/* ${APP_ROOT:-/root/app}/.env"
                    log_verbose "Existing deployment removed"
                    APP_DEPLOYED=false
                else
                    echo -e "${YELLOW}Replacement cancelled.${NC}"
                    return 1
                fi
                ;;
            2) # Return
                log_verbose "Returning to main menu"
                return 0
                ;;
        esac
    fi
    
    # Configure environment if needed
    if [ "$SKIP_ENV_SETUP" != "true" ]; then
        log_verbose "Setting up application environment..."
        if ! configure_app_environment; then
            log_error "Failed to configure application environment"
            read -p "Press Enter to return to the main menu..."
            return 1
        fi
    else
        log_verbose "Skipping environment setup as requested"
    fi
    
    # Different deployment based on deployment type
    case $DEPLOYMENT_TYPE in
        "docker-compose")
            deploy_docker_compose
            ;;
        "docker")
            deploy_docker
            ;;
        "traditional")
            deploy_traditional
            ;;
        "static")
            deploy_static
            ;;
        *)
            echo -e "${RED}Unknown deployment type: $DEPLOYMENT_TYPE${NC}"
            sleep 2
            return 1
            ;;
    esac
}

# Deploy using Docker Compose
deploy_docker_compose() {
    echo -e "${GREEN}Deploying with Docker Compose...${NC}"
    
    # We don't need to check DROPLET_IP here since it's already checked in deploy_app
    log_debug "Using droplet IP: $DROPLET_IP"
    
    # Set up remote Docker host
    export DOCKER_HOST=ssh://root@$DROPLET_IP
    
    # Check connection
    log_verbose "Checking Docker connection..."
    if ! docker info &> /dev/null; then
        log_error "Cannot connect to Docker on the remote server."
        echo -e "${YELLOW}Possible issues:${NC}"
        echo -e "  - Docker might not be installed on the droplet"
        echo -e "  - Docker daemon might not be running"
        echo -e "  - SSH connection might not be configured for Docker"
        unset DOCKER_HOST
        sleep 2
        return 1
    fi
    
    log_verbose "Docker connection successful"
    
    # Ask whether to use local docker-compose or GitHub Container Registry
    echo -e "${GREEN}How do you want to deploy?${NC}"
    SOURCE_OPTIONS=(
        "Use local docker-compose.yml file"
        "Pull images from GitHub Container Registry"
        "Return to main menu"
    )
    
    select_from_menu "Select a deployment source" "${SOURCE_OPTIONS[@]}"
    SOURCE_CHOICE=$?
    
    case $SOURCE_CHOICE in
        0) # Local docker-compose
            deploy_docker_compose_local
            ;;
        1) # GitHub Container Registry
            deploy_docker_compose_ghcr
            ;;
        2) # Return
            unset DOCKER_HOST
            return 0
            ;;
    esac
    
    # Configure web server if needed
    if [ "$WEBSERVER" != "none" ]; then
        configure_web_server
    fi
    
    unset DOCKER_HOST
    echo -e "${GREEN}✓ Application deployed with Docker Compose${NC}"
    sleep 2
}

# Deploy using local docker-compose.yml
deploy_docker_compose_local() {
    # Copy files to the droplet
    echo -e "Copying configuration files..."
    
    # Ask about docker-compose file path
    echo -e "Enter the path to your docker-compose.yml file (relative to current directory):"
    read -p "> " COMPOSE_FILE
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}File not found: $COMPOSE_FILE${NC}"
        return 1
    fi
    
    scp "$COMPOSE_FILE" root@$DROPLET_IP:/root/app/docker-compose.yml
    
    # Deploy using docker-compose
    echo -e "Deploying containers..."
    docker-compose -f docker-compose.yml -H ssh://root@$DROPLET_IP build
    docker-compose -f docker-compose.yml -H ssh://root@$DROPLET_IP up -d
}

# Deploy using GitHub Container Registry
deploy_docker_compose_ghcr() {
    echo -e "${GREEN}Deploying from GitHub Container Registry...${NC}"
    
    # Collect GitHub information
    echo -e "Enter your GitHub username:"
    read -p "> " GITHUB_USERNAME
    
    echo -e "Enter your GitHub repository (e.g., username/repository):"
    read -p "> " GITHUB_REPOSITORY
    
    echo -e "Enter the image tag to deploy (e.g., latest):"
    read -p "> " TAG
    TAG=${TAG:-latest}
    
    # Ask for GitHub token
    echo -e "Enter your GitHub Personal Access Token (will not be displayed):"
    read -s -p "> " GITHUB_TOKEN
    echo
    
    # Ask for database configuration
    echo -e "Enter database user (default: appuser):"
    read -p "> " DB_USER
    DB_USER=${DB_USER:-appuser}
    
    echo -e "Enter database password (will not be displayed, default: auto-generated):"
    read -s -p "> " DB_PASSWORD
    echo
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo -e "${YELLOW}Generated password: $DB_PASSWORD${NC}"
        echo -e "${YELLOW}Please save this password as it won't be shown again.${NC}"
    fi
    
    echo -e "Enter database name (default: appdb):"
    read -p "> " DB_NAME
    DB_NAME=${DB_NAME:-appdb}
    
    # Create app directory if it doesn't exist
    ssh root@$DROPLET_IP "mkdir -p /root/app/nginx/conf /root/app/nginx/certbot/conf /root/app/nginx/certbot/www /root/app/cache /root/app/images"
    
    # Process docker-compose template
    local template_path=$(get_template_path "docker-compose" "default.yml")
    local temp_compose_file=$(mktemp)
    
    # Export variables for template processing
    export GITHUB_REPOSITORY="$GITHUB_REPOSITORY"
    export TAG="$TAG"
    export DB_USER="$DB_USER"
    export DB_PASSWORD="$DB_PASSWORD"
    export DB_NAME="$DB_NAME"
    export API_KEY=${API_KEY:-default_key}
    export ADMIN_API_KEY=${ADMIN_API_KEY:-default_admin_key}
    export API_PORT=${API_PORT:-8000}
    export APP_PORT=${APP_PORT:-3000}
    
    # Process the template
    process_template_env "$template_path" "$temp_compose_file"
    
    # Create setup script on the droplet
    echo -e "Setting up GitHub Container Registry authentication..."
    
    # Process .env template
    local env_template=$(get_template_path "" ".env.template")
    local temp_env_file=$(mktemp)
    
    # Process the template
    process_template_env "$env_template" "$temp_env_file"
    
    cat << EOF > /tmp/setup_ghcr.sh
#!/bin/bash
# Setup script for GitHub Container Registry authentication

# Login to GitHub Container Registry
echo "$GITHUB_TOKEN" | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

# Pull the images
docker pull ghcr.io/$GITHUB_REPOSITORY/backend:$TAG
docker pull ghcr.io/$GITHUB_REPOSITORY/frontend:$TAG

# Start containers
cd /root/app
docker-compose up -d
EOF
    
    # Upload the docker-compose.yml and setup script to the droplet
    scp "$temp_compose_file" root@$DROPLET_IP:/root/app/docker-compose.yml
    scp "$temp_env_file" root@$DROPLET_IP:/root/app/.env
    scp /tmp/setup_ghcr.sh root@$DROPLET_IP:/root/app/setup_ghcr.sh
    
    # Make the setup script executable and run it
    ssh root@$DROPLET_IP "chmod +x /root/app/setup_ghcr.sh && cd /root/app && ./setup_ghcr.sh"
    
    # Clean up local temporary files
    rm "$temp_compose_file" "$temp_env_file" /tmp/setup_ghcr.sh
    
    # Reset exported variables
    unset GITHUB_REPOSITORY TAG DB_USER DB_PASSWORD DB_NAME API_KEY ADMIN_API_KEY API_PORT APP_PORT
}

# Deploy using single Docker container
deploy_docker() {
    echo -e "${GREEN}Deploying with Docker...${NC}"
    
    # Set up remote Docker host
    export DOCKER_HOST=ssh://root@$DROPLET_IP
    
    # Check connection
    if ! docker info &> /dev/null; then
        echo -e "${RED}Cannot connect to Docker on the remote server.${NC}"
        unset DOCKER_HOST
        sleep 2
        return 1
    fi
    
    # Ask about the Docker image
    echo -e "Enter the Docker image to use (e.g., nginx:latest):"
    read -p "> " DOCKER_IMAGE
    
    # Pull the image
    echo -e "Pulling Docker image: $DOCKER_IMAGE..."
    docker pull $DOCKER_IMAGE
    
    # Ask about container name
    echo -e "Enter a name for your container:"
    read -p "> " CONTAINER_NAME
    
    # Ask about ports
    echo -e "Enter port mapping (e.g., 80:80):"
    read -p "> " PORT_MAPPING
    
    # Ask about volumes
    echo -e "Do you want to mount any volumes? (y/n)"
    read -p "> " MOUNT_VOLUMES
    
    VOLUME_PARAMS=""
    if [[ $MOUNT_VOLUMES =~ ^[Yy]$ ]]; then
        echo -e "Enter volume mapping (e.g., /host/path:/container/path):"
        read -p "> " VOLUME_MAPPING
        VOLUME_PARAMS="-v $VOLUME_MAPPING"
    fi
    
    # Ask about environment variables
    echo -e "Do you want to set environment variables? (y/n)"
    read -p "> " SET_ENV_VARS
    
    ENV_PARAMS=""
    if [[ $SET_ENV_VARS =~ ^[Yy]$ ]]; then
        echo -e "Enter environment variables (e.g., KEY1=VALUE1 KEY2=VALUE2):"
        read -p "> " ENV_VARS
        
        for env_var in $ENV_VARS; do
            ENV_PARAMS="$ENV_PARAMS -e $env_var"
        done
    fi
    
    # Run the container
    echo -e "Starting Docker container..."
    docker run -d --name $CONTAINER_NAME -p $PORT_MAPPING $VOLUME_PARAMS $ENV_PARAMS --restart unless-stopped $DOCKER_IMAGE
    
    # Configure web server if needed
    if [ "$WEBSERVER" != "none" ]; then
        configure_web_server
    fi
    
    unset DOCKER_HOST
    echo -e "${GREEN}✓ Application deployed with Docker${NC}"
    sleep 2
}

# Deploy traditional application
deploy_traditional() {
    show_header "Traditional Application Deployment"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        echo -e "${RED}Error: No droplet IP found. Please create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    # Select application type
    APP_TYPES=(
        "Node.js"
        "Python"
        "Ruby"
        "PHP"
        "Other"
    )
    
    select_from_menu "Select your application type" "${APP_TYPES[@]}"
    APP_TYPE_INDEX=$?
    APP_TYPE=${APP_TYPES[$APP_TYPE_INDEX]}
    
    # Ask for application details
    echo -e "Enter the path to your application (relative to current directory):"
    read -p "> " APP_PATH
    
    if [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}Directory not found: $APP_PATH${NC}"
        sleep 2
        return 1
    fi
    
    # Create app directory on the server
    ssh root@$DROPLET_IP "mkdir -p /var/www/app"
    
    # Copy application files
    echo -e "Copying application files..."
    scp -r "$APP_PATH"/* root@$DROPLET_IP:/var/www/app/
    
    # Install dependencies based on application type
    case $APP_TYPE_INDEX in
        0) # Node.js
            echo -e "Installing Node.js dependencies..."
            ssh root@$DROPLET_IP "apt-get update && apt-get install -y nodejs npm && cd /var/www/app && npm install --production"
            
            # Create .env file
            echo -e "Creating .env file..."
            local env_template=$(get_template_path "" ".env.template")
            local temp_env_file=$(mktemp)
            
            # Set variables
            echo -e "Enter your database user (default: appuser):"
            read -p "> " DB_USER
            DB_USER=${DB_USER:-appuser}
            
            echo -e "Enter your database password (default: auto-generated):"
            read -s -p "> " DB_PASSWORD
            echo
            if [ -z "$DB_PASSWORD" ]; then
                DB_PASSWORD=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
                echo -e "${YELLOW}Generated password: $DB_PASSWORD${NC}"
                echo -e "${YELLOW}Please save this password as it won't be shown again.${NC}"
            fi
            
            echo -e "Enter your database name (default: appdb):"
            read -p "> " DB_NAME
            DB_NAME=${DB_NAME:-appdb}
            
            echo -e "Enter your API port (default: 8000):"
            read -p "> " API_PORT
            API_PORT=${API_PORT:-8000}
            
            echo -e "Enter your application port (default: 3000):"
            read -p "> " APP_PORT
            APP_PORT=${APP_PORT:-3000}
            
            # Export variables for template
            export DB_USER="$DB_USER"
            export DB_PASSWORD="$DB_PASSWORD"
            export DB_NAME="$DB_NAME"
            export API_KEY=${API_KEY:-default_key}
            export ADMIN_API_KEY=${ADMIN_API_KEY:-default_admin_key}
            export GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-username/repository}
            export TAG=${TAG:-latest}
            export PUBLIC_API_URL=${PUBLIC_API_URL:-http://localhost:8000}
            export APP_PORT="$APP_PORT"
            export API_PORT="$API_PORT"
            
            # Process the template
            process_template_env "$env_template" "$temp_env_file"
            
            # Upload the .env file
            scp "$temp_env_file" root@$DROPLET_IP:/var/www/app/.env
            
            # Clean up
            rm "$temp_env_file"
            
            # Reset exported variables
            unset DB_USER DB_PASSWORD DB_NAME API_KEY ADMIN_API_KEY GITHUB_REPOSITORY TAG PUBLIC_API_URL APP_PORT API_PORT
            
            # Set up process manager
            echo -e "Setting up PM2 process manager..."
            ssh root@$DROPLET_IP "npm install -g pm2 && cd /var/www/app && pm2 start npm --name \"app\" -- start && pm2 save && pm2 startup"
            ;;
        1) # Python
            echo -e "Setting up Python virtual environment..."
            ssh root@$DROPLET_IP "cd /var/www/app && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
            
            echo -e "Do you want to set up Gunicorn? (y/n)"
            read -p "> " USE_GUNICORN
            
            if [[ $USE_GUNICORN =~ ^[Yy]$ ]]; then
                ssh root@$DROPLET_IP "cd /var/www/app && source venv/bin/activate && pip install gunicorn"
                
                echo -e "Enter the WSGI application (e.g., app:app):"
                read -p "> " WSGI_APP
                
                # Create systemd service
                cat > gunicorn.service <<EOF
[Unit]
Description=Gunicorn instance to serve application
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory=/var/www/app
Environment="PATH=/var/www/app/venv/bin"
ExecStart=/var/www/app/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:8000 $WSGI_APP

[Install]
WantedBy=multi-user.target
EOF
                
                scp gunicorn.service root@$DROPLET_IP:/etc/systemd/system/gunicorn.service
                ssh root@$DROPLET_IP "systemctl enable gunicorn && systemctl start gunicorn"
                rm gunicorn.service
            fi
            ;;
        2) # Ruby
            echo -e "Installing Ruby dependencies..."
            ssh root@$DROPLET_IP "cd /var/www/app && gem install bundler && bundle install"
            
            echo -e "Do you want to set up Puma? (y/n)"
            read -p "> " USE_PUMA
            
            if [[ $USE_PUMA =~ ^[Yy]$ ]]; then
                # Create systemd service
                cat > puma.service <<EOF
[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
User=root
WorkingDirectory=/var/www/app
Environment=RACK_ENV=production
ExecStart=/usr/local/bin/bundle exec puma -C config/puma.rb
Restart=always

[Install]
WantedBy=multi-user.target
EOF
                
                scp puma.service root@$DROPLET_IP:/etc/systemd/system/puma.service
                ssh root@$DROPLET_IP "systemctl enable puma && systemctl start puma"
                rm puma.service
            fi
            ;;
        3) # PHP
            # Set up PHP-FPM
            ssh root@$DROPLET_IP "systemctl enable php7.4-fpm && systemctl start php7.4-fpm"
            ;;
    esac
    
    # Configure web server
    configure_web_server
    
    echo -e "${GREEN}✓ Application deployed${NC}"
    sleep 2
}

# Deploy static website
deploy_static() {
    echo -e "${GREEN}Deploying static website...${NC}"
    
    # Ask about static site source
    echo -e "How do you want to deploy your static site?"
    STATIC_SOURCES=(
        "Upload local files"
        "Git repository"
    )
    
    select_from_menu "Select deployment source" "${STATIC_SOURCES[@]}"
    STATIC_SOURCE_INDEX=$?
    
    # Set up web root directory
    ssh root@$DROPLET_IP "mkdir -p /var/www/html"
    
    # Deploy based on source type
    case $STATIC_SOURCE_INDEX in
        0) # Upload local files
            echo -e "Enter the local directory to upload:"
            read -p "> " LOCAL_DIR
            
            if [ ! -d "$LOCAL_DIR" ]; then
                echo -e "${RED}Directory not found: $LOCAL_DIR${NC}"
                sleep 2
                return 1
            fi
            
            # Copy files to the server
            scp -r $LOCAL_DIR/* root@$DROPLET_IP:/var/www/html/
            ;;
        1) # Git repository
            echo -e "Enter the Git repository URL:"
            read -p "> " GIT_URL
            
            echo -e "Enter the branch to deploy (default: main):"
            read -p "> " GIT_BRANCH
            GIT_BRANCH=${GIT_BRANCH:-main}
            
            ssh root@$DROPLET_IP "cd /var/www/html && git clone -b $GIT_BRANCH $GIT_URL ."
            ;;
    esac
    
    # Configure web server
    configure_web_server
    
    echo -e "${GREEN}✓ Static website deployed${NC}"
    sleep 2
}

# Configure web server (Nginx or Apache)
configure_web_server() {
    if [ "$WEBSERVER" == "none" ]; then
        return 0
    fi
    
    # Check if domain is configured
    if [ -z "$DOMAIN_NAME" ]; then
        echo -e "${YELLOW}No domain configured. Skipping web server configuration.${NC}"
        sleep 2
        return 0
    fi
    
    if [ "$WEBSERVER" == "nginx" ]; then
        configure_nginx
    elif [ "$WEBSERVER" == "apache" ]; then
        configure_apache
    fi
    
    # Set up SSL with Certbot
    echo -e "Would you like to set up SSL certificates with Let's Encrypt? (y/n)"
    read -p "> " SETUP_SSL
    
    if [[ $SETUP_SSL =~ ^[Yy]$ ]]; then
        echo -e "Enter your email address for SSL notifications:"
        read -p "> " SSL_EMAIL
        
        if [ "$WEBSERVER" == "nginx" ]; then
            ssh root@$DROPLET_IP "apt-get install -y certbot python3-certbot-nginx"
            ssh root@$DROPLET_IP "certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --email $SSL_EMAIL"
        elif [ "$WEBSERVER" == "apache" ]; then
            ssh root@$DROPLET_IP "apt-get install -y certbot python3-certbot-apache"
            ssh root@$DROPLET_IP "certbot --apache -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --email $SSL_EMAIL"
        fi
        
        echo -e "${GREEN}✓ SSL certificates installed${NC}"
    fi
}

# Configure Nginx
configure_nginx() {
    echo -e "${GREEN}Configuring Nginx...${NC}"
    
    local template_file=""
    local temp_config_file=$(mktemp)
    
    # Create Nginx configuration based on deployment type
    if [ "$DEPLOYMENT_TYPE" == "docker-compose" ] || [ "$DEPLOYMENT_TYPE" == "docker" ]; then
        # Ask for container port
        echo -e "Enter the port your container exposes (e.g., 3000):"
        read -p "> " CONTAINER_PORT
        CONTAINER_PORT=${CONTAINER_PORT:-3000}
        
        # Use docker template
        template_file=$(get_template_path "nginx" "docker.conf")
        
        # Export variables for template
        export DOMAIN_NAME="$DOMAIN_NAME"
        export CONTAINER_PORT="$CONTAINER_PORT"
        
        # Process the template
        process_template_env "$template_file" "$temp_config_file"
        
    elif [ "$DEPLOYMENT_TYPE" == "traditional" ]; then
        # Configure based on application type
        case $APP_TYPE_INDEX in
            0|1|2) # Node.js, Python, Ruby (assuming they run on a port)
                echo -e "Enter the port your application runs on (e.g., 3000):"
                read -p "> " APP_PORT
                APP_PORT=${APP_PORT:-3000}
                
                # Use app template
                template_file=$(get_template_path "nginx" "app.conf")
                
                # Export variables for template
                export DOMAIN_NAME="$DOMAIN_NAME"
                export APP_PORT="$APP_PORT"
                
                # Process the template
                process_template_env "$template_file" "$temp_config_file"
                ;;
            3) # PHP
                # Create custom PHP configuration
                cat > "$temp_config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    root /var/www/app;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
                ;;
            *)
                # Create custom configuration for other app types
                cat > "$temp_config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    root /var/www/app;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
                ;;
        esac
    elif [ "$DEPLOYMENT_TYPE" == "static" ]; then
        # Create custom static website configuration
        cat > "$temp_config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    fi
    
    # Upload and enable the Nginx configuration
    ssh root@$DROPLET_IP "apt-get update && apt-get install -y nginx"
    scp "$temp_config_file" root@$DROPLET_IP:/etc/nginx/sites-available/$DOMAIN_NAME.conf
    ssh root@$DROPLET_IP "ln -sf /etc/nginx/sites-available/$DOMAIN_NAME.conf /etc/nginx/sites-enabled/$DOMAIN_NAME.conf"
    ssh root@$DROPLET_IP "nginx -t && systemctl restart nginx"
    
    # Clean up local temp file
    rm "$temp_config_file"
    
    # Reset exported variables
    unset DOMAIN_NAME CONTAINER_PORT APP_PORT
    
    echo -e "${GREEN}✓ Nginx configured${NC}"
}

# Configure Apache
configure_apache() {
    echo -e "${GREEN}Configuring Apache...${NC}"
    
    # Create Apache configuration based on deployment type
    if [ "$DEPLOYMENT_TYPE" == "docker-compose" ] || [ "$DEPLOYMENT_TYPE" == "docker" ]; then
        # Ask for container port
        echo -e "Enter the port your container exposes (e.g., 3000):"
        read -p "> " CONTAINER_PORT
        
        cat > apache.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    
    ProxyPreserveHost On
    ProxyPass / http://localhost:$CONTAINER_PORT/
    ProxyPassReverse / http://localhost:$CONTAINER_PORT/
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    elif [ "$DEPLOYMENT_TYPE" == "traditional" ]; then
        # Configure based on application type
        case $APP_TYPE_INDEX in
            0|1|2) # Node.js, Python, Ruby (assuming they run on a port)
                echo -e "Enter the port your application runs on (e.g., 3000):"
                read -p "> " APP_PORT
                
                cat > apache.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    
    ProxyPreserveHost On
    ProxyPass / http://localhost:$APP_PORT/
    ProxyPassReverse / http://localhost:$APP_PORT/
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
                ;;
            3) # PHP
                cat > apache.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    
    DocumentRoot /var/www/app
    
    <Directory /var/www/app>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
                ;;
            *)
                cat > apache.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    
    DocumentRoot /var/www/app
    
    <Directory /var/www/app>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
                ;;
        esac
    elif [ "$DEPLOYMENT_TYPE" == "static" ]; then
        cat > apache.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    fi
    
    # Upload and enable the Apache configuration
    ssh root@$DROPLET_IP "apt-get update && apt-get install -y apache2"
    ssh root@$DROPLET_IP "a2enmod proxy proxy_http rewrite"
    scp apache.conf root@$DROPLET_IP:/etc/apache2/sites-available/$DOMAIN_NAME.conf
    ssh root@$DROPLET_IP "a2ensite $DOMAIN_NAME.conf && systemctl restart apache2"
    
    rm apache.conf
    echo -e "${GREEN}✓ Apache configured${NC}"
}

# Web server menu
webserver_menu() {
    if [ -z "$DROPLET_IP" ]; then
        show_header "Web Server Configuration"
        echo -e "${RED}No droplet found. Create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    while true; do
        show_header "Web Server Configuration"
        
        WEBSERVER_MENU_OPTIONS=(
            "Configure Nginx"
            "Configure Apache"
            "Set up SSL certificates"
            "Add custom server blocks"
            "Back to main menu"
        )
        
        select_from_menu "Select an action" "${WEBSERVER_MENU_OPTIONS[@]}"
        WEBSERVER_MENU_CHOICE=$?
        
        case $WEBSERVER_MENU_CHOICE in
            0)
                WEBSERVER="nginx"
                configure_nginx
                ;;
            1)
                WEBSERVER="apache"
                configure_apache
                ;;
            2)
                if [ -z "$DOMAIN_NAME" ]; then
                    echo -e "${RED}No domain configured. Please set up a domain first.${NC}"
                    sleep 2
                else
                    echo -e "Enter your email address for SSL notifications:"
                    read -p "> " SSL_EMAIL
                    
                    if [ "$WEBSERVER" == "nginx" ] || [ -z "$WEBSERVER" ]; then
                        ssh root@$DROPLET_IP "apt-get install -y nginx certbot python3-certbot-nginx"
                        ssh root@$DROPLET_IP "certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --email $SSL_EMAIL"
                    elif [ "$WEBSERVER" == "apache" ]; then
                        ssh root@$DROPLET_IP "apt-get install -y apache2 certbot python3-certbot-apache"
                        ssh root@$DROPLET_IP "certbot --apache -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --email $SSL_EMAIL"
                    fi
                    
                    echo -e "${GREEN}✓ SSL certificates installed${NC}"
                    sleep 2
                fi
                ;;
            3)
                echo -e "Enter path to your custom server block file:"
                read -p "> " SERVER_BLOCK_FILE
                
                if [ -f "$SERVER_BLOCK_FILE" ]; then
                    echo -e "Enter filename to save on server (e.g., mysite.conf):"
                    read -p "> " SERVER_BLOCK_NAME
                    
                    if [ "$WEBSERVER" == "nginx" ] || [ -z "$WEBSERVER" ]; then
                        ssh root@$DROPLET_IP "apt-get install -y nginx"
                        scp "$SERVER_BLOCK_FILE" root@$DROPLET_IP:/etc/nginx/sites-available/$SERVER_BLOCK_NAME
                        ssh root@$DROPLET_IP "ln -sf /etc/nginx/sites-available/$SERVER_BLOCK_NAME /etc/nginx/sites-enabled/$SERVER_BLOCK_NAME"
                        ssh root@$DROPLET_IP "nginx -t && systemctl restart nginx"
                    elif [ "$WEBSERVER" == "apache" ]; then
                        ssh root@$DROPLET_IP "apt-get install -y apache2"
                        scp "$SERVER_BLOCK_FILE" root@$DROPLET_IP:/etc/apache2/sites-available/$SERVER_BLOCK_NAME
                        ssh root@$DROPLET_IP "a2ensite $SERVER_BLOCK_NAME && systemctl restart apache2"
                    fi
                    
                    echo -e "${GREEN}✓ Custom server block uploaded and enabled${NC}"
                    sleep 2
                else
                    echo -e "${RED}File not found: $SERVER_BLOCK_FILE${NC}"
                    sleep 2
                fi
                ;;
            4)
                return 0
                ;;
        esac
    done
}

# Configure the application environment
configure_app_environment() {
    log_debug "Starting configure_app_environment function"
    
    # Verify DROPLET_IP is set and valid
    if [ -z "$DROPLET_IP" ]; then
        log_error "DROPLET_IP is empty or not set! Cannot configure environment."
        echo -e "${YELLOW}You need to create a droplet first before configuring the environment.${NC}"
        return 1
    fi
    
    log_debug "Using DROPLET_IP: $DROPLET_IP"
    echo "Configuring application environment..."
    echo -e "Using SSH connection: ${GREEN}root@$DROPLET_IP${NC}"
    
    # Test SSH connection
    log_verbose "Testing SSH connection..."
    if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP exit &>/dev/null; then
        log_error "Cannot connect to the droplet at $DROPLET_IP"
        echo -e "${YELLOW}Unable to establish SSH connection.${NC}"
        return 1
    fi
    
    ssh root@$DROPLET_IP "mkdir -p /root/app"
    
    log_verbose "Launching environment editor script..."
    
    # Use the correct path for the Python script
    SCRIPT_PATH="$DIR/edit-remote-env.py"
    log_debug "Editor script path: $SCRIPT_PATH"
    
    if [ ! -f "$SCRIPT_PATH" ]; then
        log_error "Python editor script not found at: $SCRIPT_PATH"
        echo -e "${YELLOW}The Python editor script is missing. Creating it now...${NC}"
        
        # Create the basic script if it doesn't exist
        cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env python3
# Script to edit remote .env file

import os
import sys
import subprocess
import tempfile

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 edit-remote-env.py <droplet-ip>")
        sys.exit(1)
    
    droplet_ip = sys.argv[1]
    print(f"Setting up environment file for droplet at {droplet_ip}")
    
    # Create app directory
    subprocess.run(f'ssh root@{droplet_ip} "mkdir -p /root/app"', shell=True, check=True)
    
    # Create temp file
    with tempfile.NamedTemporaryFile(delete=False, suffix='.env', mode='w+') as tmp:
        temp_file = tmp.name
        
        # Check if .env already exists on server
        result = subprocess.run(
            f'ssh root@{droplet_ip} "test -f /root/app/.env && echo YES || echo NO"',
            shell=True, 
            capture_output=True,
            text=True,
            check=True
        )
        
        if result.stdout.strip() == "YES":
            print("Existing .env found, downloading for editing...")
            subprocess.run(f'scp root@{droplet_ip}:/root/app/.env {temp_file}', shell=True, check=True)
        else:
            # Create basic template
            tmp.write("""# Database settings
DB_HOST=localhost
DB_USER=admin
DB_PASSWORD=your_secure_password
DB_NAME=appdb

# Application settings
APP_ENV=production
APP_PORT=8000
API_KEY=your_production_api_key
ADMIN_API_KEY=your_production_admin_api_key
""")
    
    # Open in editor
    editor = os.environ.get('EDITOR', 'nano')
    subprocess.run(f'{editor} {temp_file}', shell=True)
    
    # Upload file
    print("Uploading .env file to server...")
    subprocess.run(f'scp {temp_file} root@{droplet_ip}:/root/app/.env', shell=True, check=True)
    
    # Clean up
    os.unlink(temp_file)
    print("Environment setup complete!")

if __name__ == "__main__":
    main()
EOF
        
        # Make it executable
        chmod +x "$SCRIPT_PATH"
    fi
    
    log_debug "Running: python3 \"$SCRIPT_PATH\" $DROPLET_IP"
    python3 "$SCRIPT_PATH" $DROPLET_IP
    
    if [ $? -ne 0 ]; then
        log_error "Environment editor script failed with exit code $?"
        return 1
    fi
    
    echo "Environment configured successfully."
    return 0
}

# Call the environment configuration function instead of the old hard-coded section
configure_app_environment

# Check deployment status
deployment_status() {
    show_header "Deployment Status"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        log_error "No droplet IP found. Please create a droplet first."
        read -p "Press Enter to return to the main menu..."
        return 1
    fi
    
    # Verify SSH connection
    log_verbose "Verifying SSH connection to $DROPLET_IP..."
    if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$DROPLET_IP exit &>/dev/null; then
        log_error "Cannot connect to the droplet at $DROPLET_IP"
        echo -e "${YELLOW}Cannot check deployment status due to SSH connection issues.${NC}"
        read -p "Press Enter to return to the main menu..."
        return 1
    fi
    
    echo -e "${GREEN}Checking deployment status...${NC}"
    
    # Check Docker status if applicable
    if [ "$DEPLOYMENT_TYPE" = "docker-compose" ] || [ "$DEPLOYMENT_TYPE" = "docker" ]; then
        echo -e "\n${CYAN}Docker Status:${NC}"
        if ssh root@$DROPLET_IP "command -v docker &>/dev/null"; then
            ssh root@$DROPLET_IP "docker --version"
            ssh root@$DROPLET_IP "docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'"
        else
            echo -e "${YELLOW}Docker not installed or not in PATH${NC}"
        fi
    fi
    
    # Check for application directory
    echo -e "\n${CYAN}Application Directory:${NC}"
    if ssh root@$DROPLET_IP "test -d ${APP_ROOT:-/root/app}"; then
        ssh root@$DROPLET_IP "ls -la ${APP_ROOT:-/root/app} | head -n 10"
        
        # Count files
        FILE_COUNT=$(ssh root@$DROPLET_IP "find ${APP_ROOT:-/root/app} -type f | wc -l")
        echo -e "${GREEN}Total files: ${YELLOW}$FILE_COUNT${NC}"
        
        # Check .env file
        if ssh root@$DROPLET_IP "test -f ${APP_ROOT:-/root/app}/.env"; then
            ENV_COUNT=$(ssh root@$DROPLET_IP "grep -v '^#' ${APP_ROOT:-/root/app}/.env | grep '=' | wc -l")
            echo -e "${GREEN}.env file: ${YELLOW}Present with $ENV_COUNT settings${NC}"
        else
            echo -e "${YELLOW}.env file: Not found${NC}"
        fi
    else
        echo -e "${YELLOW}Application directory not found${NC}"
    fi
    
    # Check web server
    echo -e "\n${CYAN}Web Server Status:${NC}"
    if [ "$WEBSERVER" = "nginx" ]; then
        if ssh root@$DROPLET_IP "command -v nginx &>/dev/null"; then
            ssh root@$DROPLET_IP "nginx -v 2>&1"
            echo
            ssh root@$DROPLET_IP "systemctl status nginx | head -n 3"
        else
            echo -e "${YELLOW}Nginx not installed${NC}"
        fi
    elif [ "$WEBSERVER" = "apache" ]; then
        if ssh root@$DROPLET_IP "command -v apache2 &>/dev/null"; then
            ssh root@$DROPLET_IP "apache2 -v | head -n 1"
            echo
            ssh root@$DROPLET_IP "systemctl status apache2 | head -n 3"
        else
            echo -e "${YELLOW}Apache not installed${NC}"
        fi
    fi
    
    # Check connectivity
    echo -e "\n${CYAN}Connectivity:${NC}"
    if ssh root@$DROPLET_IP "command -v curl &>/dev/null"; then
        echo -e "${GREEN}Checking HTTP on localhost...${NC}"
        ssh root@$DROPLET_IP "curl -s --connect-timeout 3 http://localhost:${APP_PORT:-3000}/ -o /dev/null -w 'Status: %{http_code}' || echo 'Failed to connect'"
    fi
    
    # Check domains if configured
    if [ ! -z "$DOMAIN_NAME" ]; then
        echo -e "\n${CYAN}Domain Status:${NC}"
        echo -e "${GREEN}Domain: ${YELLOW}$DOMAIN_NAME${NC}"
        
        # Dig if available
        if ssh root@$DROPLET_IP "command -v dig &>/dev/null"; then
            ssh root@$DROPLET_IP "dig +short $DOMAIN_NAME || echo 'No DNS record'"
        else
            # Fallback to host
            ssh root@$DROPLET_IP "host $DOMAIN_NAME || echo 'No DNS record'"
        fi
        
        # Check SSL
        if ssh root@$DROPLET_IP "test -d /etc/letsencrypt/live/$DOMAIN_NAME"; then
            echo -e "${GREEN}SSL Certificate: ${YELLOW}Installed${NC}"
            CERT_EXPIRY=$(ssh root@$DROPLET_IP "openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN_NAME/cert.pem" 2>/dev/null || echo "Error reading certificate")
            echo -e "${GREEN}Certificate expiry: ${YELLOW}$CERT_EXPIRY${NC}"
        else
            echo -e "${YELLOW}SSL Certificate: Not installed${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}Status check complete.${NC}"
    read -p "Press Enter to continue..."
}