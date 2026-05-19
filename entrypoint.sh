#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if DATABASE_URL is empty and MYSQL_URL exists
# This is commonly used on Railway where MYSQL_URL is provided automatically
if [ -z "$DATABASE_URL" ] && [ -n "$MYSQL_URL" ]; then
    
    # Set DATABASE_URL equal to MYSQL_URL
    export DATABASE_URL="$MYSQL_URL"
    
    # Display confirmation message
    echo "Exported DATABASE_URL from MYSQL_URL"
fi

# Print message before starting PHP-FPM
echo "Starting PHP-FPM..."

# Start PHP-FPM in the background
php-fpm -F &

# Save the Process ID (PID) of PHP-FPM
PHP_PID=$!

# Wait a few seconds to allow PHP-FPM to fully start
echo "Waiting for PHP-FPM to start..."
sleep 2

# Print message before starting Nginx
echo "Starting Nginx..."

# Start Nginx in the foreground
# "daemon off;" keeps Nginx running in the current process
nginx -g "daemon off;"

# Wait for the PHP-FPM background process to finish
wait $PHP_PID