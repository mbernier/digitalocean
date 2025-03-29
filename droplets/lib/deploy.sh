#!/bin/bash
# Deployment functions

# Deploy the application
deploy_app() {
    show_header "Deploy Application"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        echo -e "${RED}Error: No droplet IP found. Please create a droplet first.${NC}"
        sleep 2
        return 1
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
    
    # Set up remote Docker host
    export DOCKER_HOST=ssh://root@$DROPLET_IP
    
    # Check connection
    if ! docker info &> /dev/null; then
        echo -e "${RED}Cannot connect to Docker on the remote server.${NC}"
        unset DOCKER_HOST
        sleep 2
        return 1
    fi
    
    # Copy files to the droplet
    echo -e "Copying configuration files..."
    ssh root@$DROPLET_IP "mkdir -p /root/app"
    
    # Ask about docker-compose file path
    echo -e "Enter the path to your docker-compose.yml file (relative to current directory):"
    read -p "> " COMPOSE_FILE
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}File not found: $COMPOSE_FILE${NC}"
        unset DOCKER_HOST
        sleep 2
        return 1
    fi
    
    scp "$COMPOSE_FILE" root@$DROPLET_IP:/root/app/docker-compose.yml
    
    # Check if .env.example exists
    if [ -f ".env.example" ]; then
        scp .env.example root@$DROPLET_IP:/root/app/
        ssh root@$DROPLET_IP "cd /root/app && cp .env.example .env"
        
        echo -e "${GREEN}Update the .env file with production values:${NC}"
        ssh root@$DROPLET_IP "nano /root/app/.env"
    else
        echo -e "${YELLOW}No .env.example file found. Creating an empty .env file...${NC}"
        ssh root@$DROPLET_IP "touch /root/app/.env"
        echo -e "${GREEN}Update the .env file with production values:${NC}"
        ssh root@$DROPLET_IP "nano /root/app/.env"
    fi
    
    # Deploy using docker-compose
    echo -e "Deploying containers..."
    docker-compose -f docker-compose.yml -H ssh://root@$DROPLET_IP build
    docker-compose -f docker-compose.yml -H ssh://root@$DROPLET_IP up -d
    
    # Configure web server if needed
    if [ "$WEBSERVER" != "none" ]; then
        configure_web_server
    fi
    
    unset DOCKER_HOST
    echo -e "${GREEN}✓ Application deployed with Docker Compose${NC}"
    sleep 2
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

# Deploy traditional application (non-Docker)
deploy_traditional() {
    echo -e "${GREEN}Deploying traditional application...${NC}"
    
    # Ask about application type
    APP_TYPES=(
        "Node.js"
        "Python"
        "Ruby"
        "PHP"
        "Other"
    )
    
    select_from_menu "Select your application type" "${APP_TYPES[@]}"
    APP_TYPE_INDEX=$?
    
    # Set up the application
    case $APP_TYPE_INDEX in
        0) # Node.js
            ssh root@$DROPLET_IP "curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && apt-get install -y nodejs"
            ;;
        1) # Python
            ssh root@$DROPLET_IP "apt-get install -y python3 python3-pip python3-venv"
            ;;
        2) # Ruby
            ssh root@$DROPLET_IP "apt-get install -y ruby-full"
            ;;
        3) # PHP
            ssh root@$DROPLET_IP "apt-get install -y php php-fpm php-mysql"
            ;;
        4) # Other
            echo -e "No specific runtime installed."
            ;;
    esac
    
    # Ask about application source
    echo -e "How do you want to deploy your application?"
    SOURCE_TYPES=(
        "Git repository"
        "Upload local files"
        "Manual setup"
    )
    
    select_from_menu "Select deployment source" "${SOURCE_TYPES[@]}"
    SOURCE_TYPE_INDEX=$?
    
    # Deploy based on source type
    case $SOURCE_TYPE_INDEX in
        0) # Git repository
            echo -e "Enter the Git repository URL:"
            read -p "> " GIT_URL
            
            echo -e "Enter the branch to deploy (default: main):"
            read -p "> " GIT_BRANCH
            GIT_BRANCH=${GIT_BRANCH:-main}
            
            ssh root@$DROPLET_IP "mkdir -p /var/www/app && cd /var/www/app && git clone -b $GIT_BRANCH $GIT_URL ."
            ;;
        1) # Upload local files
            echo -e "Enter the local directory to upload:"
            read -p "> " LOCAL_DIR
            
            if [ ! -d "$LOCAL_DIR" ]; then
                echo -e "${RED}Directory not found: $LOCAL_DIR${NC}"
                sleep 2
                return 1
            fi
            
            ssh root@$DROPLET_IP "mkdir -p /var/www/app"
            scp -r $LOCAL_DIR/* root@$DROPLET_IP:/var/www/app/
            ;;
        2) # Manual setup
            echo -e "Please set up your application manually."
            echo -e "SSH into your server with: ssh root@$DROPLET_IP"
            ;;
    esac
    
    # Run application setup if needed
    if [ $SOURCE_TYPE_INDEX -ne 2 ]; then
        case $APP_TYPE_INDEX in
            0) # Node.js
                echo -e "Running npm install..."
                ssh root@$DROPLET_IP "cd /var/www/app && npm install"
                
                echo -e "Do you want to set up a process manager (PM2)? (y/n)"
                read -p "> " USE_PM2
                
                if [[ $USE_PM2 =~ ^[Yy]$ ]]; then
                    ssh root@$DROPLET_IP "npm install -g pm2"
                    
                    echo -e "Enter the start script (e.g., app.js or npm start):"
                    read -p "> " START_SCRIPT
                    
                    ssh root@$DROPLET_IP "cd /var/www/app && pm2 start $START_SCRIPT --name app && pm2 save && pm2 startup"
                fi
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
    fi
    
    # Configure web server
    configure_web_server
    
    echo -e "${GREEN}✓ Application deployed using traditional method${NC}"
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
    
    # Create Nginx configuration based on deployment type
    if [ "$DEPLOYMENT_TYPE" == "docker-compose" ] || [ "$DEPLOYMENT_TYPE" == "docker" ]; then
        # Ask for container port
        echo -e "Enter the port your container exposes (e.g., 3000):"
        read -p "> " CONTAINER_PORT
        
        cat > nginx.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:$CONTAINER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
    elif [ "$DEPLOYMENT_TYPE" == "traditional" ]; then
        # Configure based on application type
        case $APP_TYPE_INDEX in
            0|1|2) # Node.js, Python, Ruby (assuming they run on a port)
                echo -e "Enter the port your application runs on (e.g., 3000):"
                read -p "> " APP_PORT
                
                cat > nginx.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
                ;;
            3) # PHP
                cat > nginx.conf <<EOF
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
                cat > nginx.conf <<EOF
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
        cat > nginx.conf <<EOF
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
    scp nginx.conf root@$DROPLET_IP:/etc/nginx/sites-available/$DOMAIN_NAME.conf
    ssh root@$DROPLET_IP "ln -sf /etc/nginx/sites-available/$DOMAIN_NAME.conf /etc/nginx/sites-enabled/$DOMAIN_NAME.conf"
    ssh root@$DROPLET_IP "nginx -t && systemctl restart nginx"
    
    rm nginx.conf
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
