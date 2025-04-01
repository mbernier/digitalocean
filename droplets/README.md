# DigitalOcean Deployment Wizard

A comprehensive, interactive script for deploying applications to DigitalOcean droplets with support for multiple deployment types, cloud-init provisioning, automatic domain configuration, and data migration.

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
- 🧠 **Language detection** with smart package recommendations

## Requirements

- bash (version 4+)
- [doctl](https://github.com/digitalocean/doctl) - DigitalOcean CLI
- An SSH key added to your DigitalOcean account
- A DigitalOcean account with API access

## Installation

1. Clone this repository or download the scripts to your project:
```bash
git clone https://github.com/mbernier/digitalocean droplets
cd droplets
```

2. Make the scripts executable:
```bash
chmod +x do_deploy.sh lib/*.sh
```

## Usage

1. Make sure you're in the project directory
2. Run the deployment wizard:
   ```
   ./do_deploy.sh
   ```
   
   With logging options:
   ```
   # For verbose output
   ./do_deploy.sh --verbose

   # For debug output
   ./do_deploy.sh --debug

   # For quiet output (errors only)
   ./do_deploy.sh --quiet
   
   # Run all system checks with debug output
   ./do_deploy.sh --check --debug
   ```
   
3. Follow the interactive menu to:
   - Create a DigitalOcean droplet
   - Configure a domain
   - Deploy your application
   - Migrate your data

### Logging Levels

The script supports different logging levels:

- **Quiet (`--quiet` or `-q`)**: Only errors and essential information
- **Normal** (default): Standard user-facing messages
- **Verbose (`--verbose` or `-v`)**: Additional information about script operations
- **Debug (`--debug` or `-d`)**: Detailed information for troubleshooting, including command outputs

When troubleshooting issues, use `--debug` to see the full execution flow and all command outputs.

### Configuration Files

The script creates and uses two main configuration files:

1. `.do_deploy.conf` - Contains droplet-specific information:
   - Droplet name, IP, region, size, and image
   - Creation timestamp
   - Domain configuration (if set up)

2. `.do_deploy.project` - Contains project-specific information:
   - Project name
   - Deployment type
   - Selected languages and suggested packages
   - Web server and database selections

These files are automatically created during the script execution but can also be manually configured.

### Editing Files

When you need to edit files (like .env), the script will use a Python-based editor that:
1. Downloads the file from the server to your local machine
2. Opens it in your default text editor
3. Uploads it back to the server after you save changes

This approach avoids terminal encoding issues that can occur when editing remote files directly.

## Using with an Existing Droplet

If you already have a DigitalOcean droplet, you can use this script without creating a new one:

1. Create a configuration file for your existing droplet:
```bash
touch .do_deploy.conf
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
./do_deploy.sh
```

## Detailed Usage

### Project Configuration

When first running the script, you'll be asked to configure your project:

- **Project Name**: A name for your project
- **Deployment Type**: How your application will be deployed
- **Web Server**: Which web server to use (Nginx, Apache, or none)
- **Database**: What database your application uses
- **Programming Languages**: Languages used in your project (Python, Node.js, etc.)

Based on your selections, the script will suggest appropriate packages to install on your droplet. This configuration is saved for future use.

### Droplet Creation

The script provides options for:

- Droplet name
- Region selection
- Size selection
- Image selection (OS)
- SSH key selection
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
./do_deploy.sh
# Follow prompts to:
# 1. Select "Docker Compose" as deployment type
# 2. Create a droplet or use existing
# 3. Configure domain
# 4. Select docker-compose.yml file
# 5. Set up environment variables
```

### Deploying a Static Website

```bash
./do_deploy.sh
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
./do_deploy.sh
# From main menu:
# 1. Select "Migrate data"
# 2. Choose "Set up database backup schedule"
# 3. Select database type
# 4. Configure backup frequency
```

## File Structure

```
./
├── do_deploy.sh              # Main script
├── .do_deploy.conf           # Droplet configuration (created by script)
├── .do_deploy.project        # Project configuration (created by script)
├── .cloud-init.yml           # Cloud-init template (created by script)
├── lib/
│   ├── utils.sh              # Utility functions
│   ├── droplet.sh            # Droplet creation functions
│   ├── domain.sh             # Domain configuration functions
│   ├── deploy.sh             # Deployment functions
│   ├── data_migrate.sh       # Data migration functions
│   ├── cloud_init.sh         # Cloud-init provisioning functions
│   └── utils/                # Additional utility scripts
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

3. **Missing or invalid droplet IP**:
   If you see error messages about missing or invalid droplet IP, you need to create a droplet first or fix your configuration file.
   
   Solutions:
   - Select "Create a new droplet" from the main menu if you haven't created one yet
   - If your configuration file contains an invalid IP, edit or remove the file at `.do_deploy.conf`
   - Run with debug output to see exactly what's happening: `./do_deploy.sh --debug`

4. **Issues with the file editor**:
   The script has been designed to make file editing easier by:  
   - Downloading files from the server to edit locally  
   - Using your system's default editor instead of opening an editor over SSH  
   - Uploading the file back to the server after editing  
   
   When prompted to edit a file, simply:  
   1. Press Enter to open your local editor  
   2. Make your changes and save  
   3. Close the editor  
   4. Confirm the upload  
   
   This avoids terminal encoding issues that can cause strange characters to appear when editing files directly over SSH.

5. **DNS propagation wait**:
   If your domain isn't resolving to your droplet immediately, this is normal. DNS changes can take up to 48 hours to propagate globally, but often happen within a few hours.

### Debugging

For advanced debugging, run the script with bash's debug mode:
```bash
bash -x ./do_deploy.sh
```

## GitHub Container Registry Deployment

You can deploy directly from GitHub Container Registry (GHCR) using our enhanced deployment scripts. This lets you benefit from CI/CD workflows that build and publish images to GHCR, while keeping your production environment updated with the latest versions.

### Manual Deployment from GHCR

1. Run the deployment wizard:
   ```bash
   ./do_deploy.sh
   ```

2. Select "Deploy application" from the menu

3. Choose "Deploy with Docker Compose" 

4. Select "Pull images from GitHub Container Registry"

5. Follow the prompts to enter your GitHub information and Personal Access Token

### Setting Up Automatic Updates

To keep your production environment updated with the latest images from GHCR:

1. Upload the auto-update script to your Digital Ocean droplet:
   ```bash
   scp ghcr_auto_update.sh root@YOUR_DROPLET_IP:/root/
   ```

2. Make it executable:
   ```bash
   ssh root@YOUR_DROPLET_IP "chmod +x /root/ghcr_auto_update.sh"
   ```

3. Set up a cron job to run the script regularly:
   ```bash
   ssh root@YOUR_DROPLET_IP "echo '0 4 * * * /root/ghcr_auto_update.sh YOUR_GITHUB_USERNAME YOUR_GITHUB_REPO latest >> /root/cron.log 2>&1' | crontab -"
   ```
   This example runs the update script every day at 4 AM, pulling the 'latest' tag.

### Security Considerations

- Use a dedicated GitHub Personal Access Token with minimal permissions (just `read:packages`)
- Consider setting up a dedicated service account in GitHub for production deployments
- Store your GitHub credentials securely using environment variables or a secrets manager

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- Based on [DigitalOcean's documentation](https://www.digitalocean.com/docs)
- Inspired by various community deployment scripts
- Created by Matt Bernier (@mbernier)