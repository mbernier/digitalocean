#!/bin/bash
# Data migration functions

# Migrate data to the server
migrate_data() {
    show_header "Data Migration"
    
    # Check if we have a droplet IP
    if [ -z "$DROPLET_IP" ]; then
        echo -e "${RED}Error: No droplet IP found. Please create a droplet first.${NC}"
        sleep 2
        return 1
    fi
    
    # Ask user to choose migration method
    MIGRATION_OPTIONS=(
        "Export a local database to JSON and import on server"
        "Copy specific files to the server"
        "Run a custom SQL script on the server"
        "Set up database backup schedule"
        "Restore from backup"
    )
    
    select_from_menu "Select a migration method" "${MIGRATION_OPTIONS[@]}"
    MIGRATION_METHOD=$?
    
    case $MIGRATION_METHOD in
        0) # Export database
            migrate_export_database
            ;;
        1) # Copy specific files
            migrate_copy_files
            ;;
        2) # Run SQL script
            migrate_run_sql
            ;;
        3) # Set up database backup
            setup_database_backup
            ;;
        4) # Restore from backup
            restore_from_backup
            ;;
    esac
}

# Export a local database to JSON and import on server
migrate_export_database() {
    echo -e "Enter the path to your export script:"
    read -p "> " EXPORT_SCRIPT
    
    if [ ! -f "$EXPORT_SCRIPT" ]; then
        echo -e "${RED}File not found: $EXPORT_SCRIPT${NC}"
        sleep 2
        return 1
    fi
    
    echo -e "Running export script..."
    $EXPORT_SCRIPT
    
    # Find the latest export file
    EXPORT_FILE=$(ls -t database_export/export_*.json 2>/dev/null | head -1)
    if [ -z "$EXPORT_FILE" ]; then
        echo -e "${RED}No export file found.${NC}"
        sleep 2
        return 1
    fi
    
    echo -e "Using export file: $EXPORT_FILE"
    
    # Copy the export file to the droplet
    echo -e "Copying export file to droplet..."
    ssh root@$DROPLET_IP "mkdir -p /root/app/database_export"
    scp $EXPORT_FILE root@$DROPLET_IP:/root/app/database_export/
    
    # Enter import command
    echo -e "Enter the command to import data on the server:"
    echo -e "(Use \$FILENAME as a placeholder for the export file name)"
    read -p "> " IMPORT_COMMAND
    
    FILENAME=$(basename $EXPORT_FILE)
    IMPORT_COMMAND=${IMPORT_COMMAND//\$FILENAME/$FILENAME}
    
    # Run the import command
    echo -e "Running import command on the server..."
    
    if [[ $IMPORT_COMMAND == *"docker"* ]] || [[ $IMPORT_COMMAND == *"docker-compose"* ]]; then
        export DOCKER_HOST=ssh://root@$DROPLET_IP
        eval $IMPORT_COMMAND
        unset DOCKER_HOST
    else
        ssh root@$DROPLET_IP "$IMPORT_COMMAND"
    fi
    
    echo -e "${GREEN}✓ Database exported and imported${NC}"
    sleep 2
}

# Copy specific files to the server
migrate_copy_files() {
    echo -e "Enter the path to the files you want to copy (can use wildcards):"
    read -p "> " FILES_TO_COPY
    
    echo -e "Enter the destination path on the server:"
    read -p "> " DEST_PATH
    
    # Create destination directory
    ssh root@$DROPLET_IP "mkdir -p $DEST_PATH"
    
    # Copy files
    scp $FILES_TO_COPY root@$DROPLET_IP:$DEST_PATH
    
    echo -e "${GREEN}✓ Files copied to server${NC}"
    sleep 2
}

# Run a custom SQL script on the server
migrate_run_sql() {
    echo -e "Enter the path to your SQL script:"
    read -p "> " SQL_SCRIPT
    
    if [ ! -f "$SQL_SCRIPT" ]; then
        echo -e "${RED}File not found: $SQL_SCRIPT${NC}"
        sleep 2
        return 1
    fi
    
    # Ask about database type
    DB_TYPES=(
        "PostgreSQL"
        "MySQL/MariaDB"
    )
    
    select_from_menu "Select your database type" "${DB_TYPES[@]}"
    DB_TYPE_INDEX=$?
    
    echo -e "Enter the database connection details:"
    echo -e "Database name:"
    read -p "> " DB_NAME
    echo -e "Database user:"
    read -p "> " DB_USER
    echo -e "Database password:"
    read -s -p "> " DB_PASSWORD
    echo
    
    # Copy SQL script to server
    scp $SQL_SCRIPT root@$DROPLET_IP:/tmp/migrate.sql
    
    # Run SQL script
    if [ $DB_TYPE_INDEX -eq 0 ]; then
        # PostgreSQL
        ssh root@$DROPLET_IP "PGPASSWORD='$DB_PASSWORD' psql -U $DB_USER -d $DB_NAME -f /tmp/migrate.sql && rm /tmp/migrate.sql"
    else
        # MySQL/MariaDB
        ssh root@$DROPLET_IP "mysql -u $DB_USER -p'$DB_PASSWORD' $DB_NAME < /tmp/migrate.sql && rm /tmp/migrate.sql"
    fi
    
    echo -e "${GREEN}✓ SQL script executed on server${NC}"
    sleep 2
}

# Set up database backup schedule
setup_database_backup() {
    echo -e "${GREEN}Setting up database backup schedule...${NC}"
    
    # Ask about database type
    DB_TYPES=(
        "PostgreSQL"
        "MySQL/MariaDB"
        "MongoDB"
    )
    
    select_from_menu "Select your database type" "${DB_TYPES[@]}"
    DB_TYPE_INDEX=$?
    
    echo -e "Enter the database connection details:"
    echo -e "Database name:"
    read -p "> " DB_NAME
    echo -e "Database user:"
    read -p "> " DB_USER
    echo -e "Database password:"
    read -s -p "> " DB_PASSWORD
    echo
    
    echo -e "Enter backup directory on server (default: /root/backups):"
    read -p "> " BACKUP_DIR
    BACKUP_DIR=${BACKUP_DIR:-/root/backups}
    
    echo -e "Select backup frequency:"
    BACKUP_FREQUENCIES=(
        "Daily"
        "Weekly"
        "Monthly"
    )
    
    select_from_menu "Select backup frequency" "${BACKUP_FREQUENCIES[@]}"
    BACKUP_FREQ_INDEX=$?
    
    # Create backup script based on database type
    if [ $DB_TYPE_INDEX -eq 0 ]; then
        # PostgreSQL
        cat > backup.sh <<EOF
#!/bin/bash
# PostgreSQL backup script
BACKUP_DIR="$BACKUP_DIR"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
mkdir -p \$BACKUP_DIR
PGPASSWORD='$DB_PASSWORD' pg_dump -U $DB_USER -d $DB_NAME -f \$BACKUP_DIR/$DB_NAME\_\$TIMESTAMP.sql
gzip \$BACKUP_DIR/$DB_NAME\_\$TIMESTAMP.sql
find \$BACKUP_DIR -name "$DB_NAME\_*.sql.gz" -type f -mtime +30 -delete
EOF
    elif [ $DB_TYPE_INDEX -eq 1 ]; then
        # MySQL/MariaDB
        cat > backup.sh <<EOF
#!/bin/bash
# MySQL backup script
BACKUP_DIR="$BACKUP_DIR"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
mkdir -p \$BACKUP_DIR
mysqldump -u $DB_USER -p'$DB_PASSWORD' $DB_NAME > \$BACKUP_DIR/$DB_NAME\_\$TIMESTAMP.sql
gzip \$BACKUP_DIR/$DB_NAME\_\$TIMESTAMP.sql
find \$BACKUP_DIR -name "$DB_NAME\_*.sql.gz" -type f -mtime +30 -delete
EOF
    else
        # MongoDB
        cat > backup.sh <<EOF
#!/bin/bash
# MongoDB backup script
BACKUP_DIR="$BACKUP_DIR"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
mkdir -p \$BACKUP_DIR
mongodump --host localhost --db $DB_NAME --username $DB_USER --password $DB_PASSWORD --out \$BACKUP_DIR/mongo_\$TIMESTAMP
tar -zcf \$BACKUP_DIR/mongo_\$TIMESTAMP.tar.gz \$BACKUP_DIR/mongo_\$TIMESTAMP
rm -rf \$BACKUP_DIR/mongo_\$TIMESTAMP
find \$BACKUP_DIR -name "mongo_*.tar.gz" -type f -mtime +30 -delete
EOF
    fi
    
    # Set up backup cron job
    case $BACKUP_FREQ_INDEX in
        0) # Daily
            CRON_SCHEDULE="0 2 * * *"
            ;;
        1) # Weekly
            CRON_SCHEDULE="0 2 * * 0"
            ;;
        2) # Monthly
            CRON_SCHEDULE="0 2 1 * *"
            ;;
    esac
    
    # Copy backup script to server and set up cron job
    scp backup.sh root@$DROPLET_IP:/root/backup.sh
    ssh root@$DROPLET_IP "chmod +x /root/backup.sh && mkdir -p $BACKUP_DIR && echo '$CRON_SCHEDULE /root/backup.sh' > /tmp/backup-cron && crontab /tmp/backup-cron && rm /tmp/backup-cron"
    
    rm backup.sh
    
    echo -e "${GREEN}✓ Database backup schedule configured${NC}"
    sleep 2
}

# Restore from backup
restore_from_backup() {
    echo -e "${GREEN}Restoring from database backup...${NC}"
    
    # Ask about backup location
    echo -e "Is the backup file local or on the server? (local/server)"
    read -p "> " BACKUP_LOCATION
    
    # Ask about database type
    DB_TYPES=(
        "PostgreSQL"
        "MySQL/MariaDB"
        "MongoDB"
    )
    
    select_from_menu "Select your database type" "${DB_TYPES[@]}"
    DB_TYPE_INDEX=$?
    
    echo -e "Enter the database connection details:"
    echo -e "Database name:"
    read -p "> " DB_NAME
    echo -e "Database user:"
    read -p "> " DB_USER
    echo -e "Database password:"
    read -s -p "> " DB_PASSWORD
    echo
    
    if [[ $BACKUP_LOCATION == "local" ]]; then
        # Local backup file
        echo -e "Enter the path to your backup file:"
        read -p "> " BACKUP_FILE
        
        if [ ! -f "$BACKUP_FILE" ]; then
            echo -e "${RED}File not found: $BACKUP_FILE${NC}"
            sleep 2
            return 1
        fi
        
        # Copy backup file to server
        scp $BACKUP_FILE root@$DROPLET_IP:/tmp/backup_file
        REMOTE_BACKUP_FILE="/tmp/backup_file"
    else
        # Server backup file
        echo -e "Enter the path to your backup file on the server:"
        read -p "> " REMOTE_BACKUP_FILE
        
        # Check if file exists on server
        if ! ssh root@$DROPLET_IP "test -f $REMOTE_BACKUP_FILE"; then
            echo -e "${RED}File not found on server: $REMOTE_BACKUP_FILE${NC}"
            sleep 2
            return 1
        fi
    fi
    
    # Restore based on database type
    if [ $DB_TYPE_INDEX -eq 0 ]; then
        # PostgreSQL
        if [[ $REMOTE_BACKUP_FILE == *.gz ]]; then
            ssh root@$DROPLET_IP "gunzip -c $REMOTE_BACKUP_FILE | PGPASSWORD='$DB_PASSWORD' psql -U $DB_USER -d $DB_NAME"
        else
            ssh root@$DROPLET_IP "PGPASSWORD='$DB_PASSWORD' psql -U $DB_USER -d $DB_NAME -f $REMOTE_BACKUP_FILE"
        fi
    elif [ $DB_TYPE_INDEX -eq 1 ]; then
        # MySQL/MariaDB
        if [[ $REMOTE_BACKUP_FILE == *.gz ]]; then
            ssh root@$DROPLET_IP "gunzip -c $REMOTE_BACKUP_FILE | mysql -u $DB_USER -p'$DB_PASSWORD' $DB_NAME"
        else
            ssh root@$DROPLET_IP "mysql -u $DB_USER -p'$DB_PASSWORD' $DB_NAME < $REMOTE_BACKUP_FILE"
        fi
    else
        # MongoDB
        if [[ $REMOTE_BACKUP_FILE == *.tar.gz ]]; then
            ssh root@$DROPLET_IP "mkdir -p /tmp/mongo_restore && tar -xzf $REMOTE_BACKUP_FILE -C /tmp/mongo_restore && mongorestore --db $DB_NAME --username $DB_USER --password $DB_PASSWORD /tmp/mongo_restore/*/mongo_*/$DB_NAME && rm -rf /tmp/mongo_restore"
        else
            echo -e "${RED}MongoDB backups should be tar.gz files${NC}"
            sleep 2
            return 1
        fi
    fi
    
    # Clean up temp file if it was uploaded
    if [[ $BACKUP_LOCATION == "local" ]]; then
        ssh root@$DROPLET_IP "rm $REMOTE_BACKUP_FILE"
    fi
    
    echo -e "${GREEN}✓ Database restored from backup${NC}"
    sleep 2
}
