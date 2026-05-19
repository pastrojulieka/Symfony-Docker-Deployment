# Use PHP 8.3 with PHP-FPM as the build stage container.
FROM php:8.3-fpm AS builder

# Set /app as the default directory inside the container.
WORKDIR /app

# Update package lists and install required system packages.
RUN apt-get update && apt-get install -y \
    
    # Install Git for cloning repositories and version control.
    git \
    
    # Install unzip for extracting compressed files.
    unzip \
    
    # Install curl for downloading files and making requests.
    curl \
    
    # Install Node.js for frontend asset management.
    nodejs \
    
    # Install npm for JavaScript package management.
    npm \
    
    # Install PHP PDO and MySQL extensions.
    && docker-php-ext-install pdo pdo_mysql \
    
    # Remove cached package lists to reduce image size.
    && rm -rf /var/lib/apt/lists/*

# Download and install Composer globally.
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Allow Composer commands to run with root privileges.
ENV COMPOSER_ALLOW_SUPERUSER=1

# Copy Composer dependency files into the container.
COPY composer.json composer.lock ./

# Install PHP dependencies without running scripts.
RUN composer install --no-interaction --no-scripts --optimize-autoloader

# Copy all project files into the container.
COPY . .

# Create a default .env file if it does not exist.
RUN if [ ! -f /app/.env ]; then \
    
    # Set database connection URL using DATABASE_URL or MYSQL_URL.
    DB_URL=${DATABASE_URL:-${MYSQL_URL:-mysql://root@127.0.0.1:3306/app_db?serverVersion=8.0}}; \
    
    # Write default environment variables into the .env file.
    echo "APP_ENV=${APP_ENV:-prod}\nAPP_DEBUG=${APP_DEBUG:-false}\nAPP_SECRET=${APP_SECRET:-ChangeMe}\nDEFAULT_URI=${DEFAULT_URI:-http://localhost}\nDATABASE_URL=$DB_URL\nMAILER_DSN=${MAILER_DSN:-null://null}\nMESSENGER_TRANSPORT_DSN=${MESSENGER_TRANSPORT_DSN:-doctrine://default?auto_setup=0}\n" > /app/.env; \
    
    # End the conditional statement.
    fi

# Reinstall dependencies with optimized autoloading for production.
RUN composer install --no-interaction --optimize-autoloader --no-ansi || true

# Install Symfony importmap frontend assets.
RUN php bin/console importmap:install --no-interaction

# Generate and warm Symfony production cache.
RUN php bin/console cache:warmup --env=prod --no-debug || true


# Start the runtime stage using PHP 8.3 with PHP-FPM.
FROM php:8.3-fpm AS runtime

# Set /app as the working directory in the runtime container.
WORKDIR /app

# Update package lists and install runtime packages.
RUN apt-get update && apt-get install -y \
    
    # Install Nginx web server.
    nginx \
    
    # Install curl for health checks and HTTP requests.
    curl \
    
    # Remove package cache files to save space.
    && rm -rf /var/lib/apt/lists/*

# Copy the built application from the builder stage.
COPY --from=builder /app /app

# Copy generated PHP extension configuration files.
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy compiled PHP extension files.
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/

# Copy the directory containing compiled PHP shared object files.
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions

# Create application runtime directories and configure permissions.
RUN mkdir -p /app/var && \
    
    # Set www-data as the owner of application files.
    chown -R www-data:www-data /app && \
    
    # Set read and execute permissions for all users.
    chmod -R 755 /app && \
    
    # Allow write permissions for the var directory.
    chmod -R 775 /app/var

# Copy the main Nginx configuration file.
COPY nginx-main.conf /etc/nginx/nginx.conf

# Remove default Nginx site configurations.
RUN rm -rf /etc/nginx/conf.d/* /etc/nginx/sites-enabled /etc/nginx/sites-available

# Copy custom Symfony Nginx site configuration.
COPY nginx.conf /etc/nginx/conf.d/symfony.conf

# Copy the container startup script into the container.
COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Make the startup script executable.
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Configure a health check to verify the application is running.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    
    # Send a request to localhost and fail if unreachable.
    CMD curl -f http://localhost/ || exit 1

# Expose port 80 for HTTP traffic.
EXPOSE 80

# Run the custom entrypoint script when the container starts.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]