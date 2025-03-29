# DigitalOcean Deployment Wizard

A comprehensive, interactive script for deploying applications to DigitalOcean droplets with support for multiple deployment types, cloud-init provisioning, automatic domain configuration, and data migration.

![DO Deploy Demo](https://example.com/do_deploy_demo.gif)

## Features

- 🚀 **Interactive UI** with color-coded menus and guided workflows
- 🖥️ **Multiple deployment types**:
  - Docker Compose (multi-container applications)
  - Single Docker container
  - Traditional applications (Node.js, Python, Ruby, PHP)
  - Static websites
- 🔧 **Cloud-init provisioning** for automatic server setup
- 🌐 **Domain configuration** with DNS guidance
- 🔒 **SSL certificate** setup with Let's Encrypt
- 🌊 **Database management** including backups and restoration
- ⚙️ **Web server configuration** for Nginx and Apache
- 🔄 **Data migration** tools for various scenarios

## Requirements

- bash (version 4+)
- [doctl](https://github.com/digitalocean/doctl) - DigitalOcean CLI
- An SSH key added to your DigitalOcean account
- A DigitalOcean account with API access

## Installation

1. Clone this repository or download the scripts to your project:
```bash
git clone https://github.com/yourusername/do-deploy.git scripts/do
```

2. Make the scripts executable:
```bash
chmod +x scripts/do/do_deploy.sh scripts/do/lib/*.sh
```

## Quick Start

Run the main script:
```bash
./scripts/do/do_deploy.sh
```

Follow the interactive prompts to:
1. Configure your project
2. Create a DigitalOcean droplet
3. Set up domain configuration
4. Deploy your application
5. Migrate your data

## Using with an Existing Droplet

If you already have a DigitalOcean droplet, you can use this script without creating a new one:

1. Create a configuration file for your existing droplet:
```bash
touch scripts/do/.do_deploy.conf
```

2. Add your droplet information to the file:
```bash
DROPLET_NAME="your-existing-droplet-name"
DROPLET_IP="your-droplet-ip"
REGION="nyc1"  # Or whatever region your droplet is in
SIZE="s-2vcpu-2gb"  # Or whatever size your droplet is
IMAGE="docker-20-04"  # Or whatever image your droplet uses
CREATED_AT="2023-07-25 12:00:00"  # Any date format will work
```

3. Run the script and skip the "Create a new droplet" option:
```bash
./scripts/do/do_deploy.sh
```

## Detailed Usage

### Project Configuration

When first running the script, you'll be asked to configure your project:

- **Project Name**: A name for your project
- **Deployment Type**: How your application will be deployed
- **Web Server**: Which web server to use (Nginx, Apache, or none)
- **Database**: What database your application uses

This configuration is saved for future use.

### Droplet Creation

The script provides options for:

- Droplet name
- Region selection
- Size selection
- Image selection (OS)
- Cloud-init configuration

Example cloud-init options:
- Package installation
- User creation with SSH keys
- Firewall configuration
- Service setup (Docker, databases, web servers)

### Domain Configuration

For setting up your domain:

- Domain name entry
- DNS record guidance
- Subdomain configuration
- DNS propagation checking

### Application Deployment

Deployment options vary based on your selected deployment type:

#### Docker Compose
```bash
# Example docker-compose.yml path entry
./docker-compose.prod.yml
```

#### Single Docker Container
```bash
# Example Docker container configuration
Image: nginx:latest
Container name: web-server
Port mapping: 80:80
```

#### Traditional Applications
For Node.js, Python, Ruby, or PHP applications:
- Runtime installation
- Git repo or file upload
- Process management (PM2, Gunicorn, etc.)
- Web server configuration

#### Static Websites
- File upload
- Web server configuration
- SSL certificate setup

### Data Migration

Options for migrating data:

- Export/import database as JSON
- Copy files to server
- Run SQL scripts
- Set up database backup schedule
- Restore from backup

## Examples

### Deploying a Docker Compose Application

```bash
./scripts/do/do_deploy.sh
# Follow prompts to:
# 1. Select "Docker Compose" as deployment type
# 2. Create a droplet or use existing
# 3. Configure domain
# 4. Select docker-compose.yml file
# 5. Set up environment variables
```

### Deploying a Static Website

```bash
./scripts/do/do_deploy.sh
# Follow prompts to:
# 1. Select "Static Website" as deployment type
# 2. Create a droplet or use existing
# 3. Configure domain
# 4. Select local directory to upload
# 5. Configure Nginx
# 6. Set up SSL certificates
```

### Setting Up Database Backups

```bash
./scripts/do/do_deploy.sh
# From main menu:
# 1. Select "Migrate data"
# 2. Choose "Set up database backup schedule"
# 3. Select database type
# 4. Configure backup frequency
```

## File Structure

```
scripts/do/
├── do_deploy.sh              # Main script
├── .do_deploy.conf           # Droplet configuration (created by script)
├── .do_deploy.project        # Project configuration (created by script)
├── lib/
│   ├── utils.sh              # Utility functions
│   ├── droplet.sh            # Droplet creation functions
│   ├── domain.sh             # Domain configuration functions
│   ├── deploy.sh             # Deployment functions
│   ├── data_migrate.sh       # Data migration functions
│   └── cloud_init.sh         # Cloud-init provisioning functions
└── README.md                 # This documentation
```

## Customization

### Adding New Deployment Types

Modify `lib/deploy.sh` and add a new deployment function. Then update the deployment type options in `lib/utils.sh`.

### Adding Custom Cloud-Init Templates

Modify `lib/cloud_init.sh` to add new cloud-init options or templates.

## Troubleshooting

### Common Issues

1. **Authentication error with doctl**:
   ```
   Error: Unable to authenticate you
   ```
   Solution: Run `doctl auth init` and follow the prompts to authenticate with your DigitalOcean API token.

2. **SSH connection issues**:
   ```
   Permission denied (publickey)
   ```
   Solution: Make sure your SSH key is added to your DigitalOcean account and that you can SSH into DigitalOcean droplets.

3. **DNS propagation wait**:
   If your domain isn't resolving to your droplet immediately, this is normal. DNS changes can take up to 48 hours to propagate globally, but often happen within a few hours.

### Debugging

For advanced debugging, run the script with bash's debug mode:
```bash
bash -x ./scripts/do/do_deploy.sh
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- Based on [DigitalOcean's documentation](https://www.digitalocean.com/docs)
- Inspired by various community deployment scripts
- Special thanks to Matt Bernier for the improvement ideas
