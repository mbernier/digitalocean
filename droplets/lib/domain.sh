#!/bin/bash
# Domain configuration functions

# Configure domain for the droplet
setup_domain() {
    show_header "Configure Domain"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        echo -e "${RED}Error: No droplet IP found. Please create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    echo -e "${GREEN}Enter your domain name (e.g., example.com):${NC}"
    read -p "> " DOMAIN_NAME
    
    if [ -z "$DOMAIN_NAME" ]; then
        echo -e "${RED}Domain name cannot be empty.${NC}"
        sleep 2
        return 1
    fi
    
    # Save domain to config
    echo "DOMAIN_NAME=\"$DOMAIN_NAME\"" >> "$CONFIG_FILE"
    
    echo -e "\n${GREEN}Domain Configuration Instructions:${NC}"
    echo -e "Go to your domain registrar's website and set up the following DNS records:"
    echo
    echo -e "1. A Record:"
    echo -e "   Host: @ (or leave empty for apex domain)"
    echo -e "   Value: ${YELLOW}$DROPLET_IP${NC}"
    echo -e "   TTL: 3600 (or default)"
    echo
    echo -e "2. A Record:"
    echo -e "   Host: www"
    echo -e "   Value: ${YELLOW}$DROPLET_IP${NC}"
    echo -e "   TTL: 3600 (or default)"
    echo
    
    # Check if they want to add other subdomains
    echo -e "${GREEN}Do you want to add additional subdomains? (y/n)${NC}"
    read -p "> " ADD_SUBDOMAINS
    
    if [[ $ADD_SUBDOMAINS =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Enter comma-separated subdomains (e.g., blog,api,admin):${NC}"
        read -p "> " SUBDOMAINS
        
        IFS=',' read -ra SUBDOMAIN_ARRAY <<< "$SUBDOMAINS"
        for subdomain in "${SUBDOMAIN_ARRAY[@]}"; do
            echo -e "3. A Record:"
            echo -e "   Host: ${subdomain}"
            echo -e "   Value: ${YELLOW}$DROPLET_IP${NC}"
            echo -e "   TTL: 3600 (or default)"
            echo
        done
        
        # Save subdomains to config
        echo "SUBDOMAINS=\"$SUBDOMAINS\"" >> "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}Have you configured these DNS records? (y/n)${NC}"
    read -p "> " DNS_CONFIGURED
    
    if [[ ! $DNS_CONFIGURED =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Please configure DNS records before continuing.${NC}"
        echo -e "You can continue with deployment and configure DNS later."
        sleep 2
    else
        echo -e "${GREEN}✓ Domain configured${NC}"
        
        # Check if they want to verify DNS propagation
        echo -e "${GREEN}Do you want to verify DNS propagation? (y/n)${NC}"
        read -p "> " VERIFY_DNS
        
        if [[ $VERIFY_DNS =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Checking DNS propagation for $DOMAIN_NAME...${NC}"
            
            RESOLVED_IP=$(dig +short $DOMAIN_NAME)
            
            if [ "$RESOLVED_IP" == "$DROPLET_IP" ]; then
                echo -e "${GREEN}DNS propagation complete! Domain resolves to your droplet.${NC}"
            else
                echo -e "${YELLOW}DNS not fully propagated yet. Current IP: $RESOLVED_IP${NC}"
                echo -e "${YELLOW}Expected IP: $DROPLET_IP${NC}"
                echo -e "${YELLOW}This can take up to 48 hours, but often happens within a few hours.${NC}"
            fi
            
            sleep 3
        fi
    fi
}