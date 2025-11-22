#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FLOWW_VERSION="latest"
INSTALL_DIR="$PWD/floww"
# Templates URL - can be overridden with environment variable for local testing
# Examples:
#   - Default (remote): https://raw.githubusercontent.com/usefloww/floww/main/install/templates
#   - Local files: file:///path/to/local/templates
#   - Local server: http://localhost:8000/templates
TEMPLATES_URL="${TEMPLATES_URL:-https://raw.githubusercontent.com/usefloww/floww/main/install/templates}"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Banner
print_banner() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║                                        ║"
    echo "║       Floww Self-Hosting Setup        ║"
    echo "║                                        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        echo ""
        echo "Please install Docker first:"
        echo "  curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    log_success "Docker found"
    
    # Check Docker daemon
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    log_success "Docker daemon is running"
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    log_success "Docker Compose found"
    
    # Check for required tools
    for tool in curl openssl; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done
    log_success "All prerequisites met"
    echo ""
}

# Get server IP
get_server_ip() {
    # Try multiple methods to get public IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "unknown")
}

# Interactive configuration
interactive_setup() {
    log_info "Starting interactive setup..."
    echo ""
    
    # Domain configuration
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Domain Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Enter your domain (e.g., floww.example.com)"
    echo "Or press Enter to use 'localhost' for testing"
    read -p "Domain: " DOMAIN
    DOMAIN=${DOMAIN:-localhost}
    
    if [[ "$DOMAIN" != "localhost" && "$DOMAIN" != "127.0.0.1" ]]; then
        get_server_ip
        echo ""
        log_warning "DNS Configuration Required:"
        echo ""
        echo "  Add this A record to your DNS provider:"
        echo "  ┌─────────────────────────────────────┐"
        echo "  │ Type: A                             │"
        echo "  │ Name: $(printf "%-28s" "$DOMAIN") │"
        echo "  │ Value: $(printf "%-27s" "$SERVER_IP") │"
        echo "  │ TTL: 3600                           │"
        echo "  └─────────────────────────────────────┘"
        echo ""
        read -p "Press Enter once DNS is configured (or continue anyway)..."
    fi

    # Determine protocol based on domain
    if [[ "$DOMAIN" == "localhost" || "$DOMAIN" == "127.0.0.1" ]]; then
        PROTOCOL="http"
        WS_PROTOCOL="ws"
    else
        PROTOCOL="https"
        WS_PROTOCOL="wss"
    fi

    # Admin email
    echo ""
    read -p "Admin email (for SSL certificates) [admin@$DOMAIN]: " ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-admin@$DOMAIN}

    # Set authentication to password (self-hosting default)
    AUTH_TYPE="password"
    
    # Organization details
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "2. Organization Details"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Organization name (slug) [default]: " ORG_NAME
    ORG_NAME=${ORG_NAME:-default}
    
    read -p "Organization display name [My Organization]: " ORG_DISPLAY_NAME
    ORG_DISPLAY_NAME=${ORG_DISPLAY_NAME:-My Organization}
    
    # Docker registry (optional)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "3. Docker Registry (Optional)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Enable private Docker registry authentication? [y/N]: " ENABLE_REGISTRY_AUTH
    if [[ $ENABLE_REGISTRY_AUTH =~ ^[Yy]$ ]]; then
        read -p "Registry username: " DOCKER_REGISTRY_USER
        read -sp "Registry password: " DOCKER_REGISTRY_PASSWORD
        echo ""
    else
        DOCKER_REGISTRY_USER=""
        DOCKER_REGISTRY_PASSWORD=""
    fi
}

# Generate secrets
generate_secrets() {
    log_info "Generating secure secrets..."

    DB_PASSWORD=$(openssl rand -hex 16)
    CENTRIFUGO_API_KEY=$(openssl rand -hex 32)
    SESSION_SECRET_KEY=$(openssl rand -hex 64)
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    WORKFLOW_JWT_SECRET=$(openssl rand -hex 64)
    CENTRIFUGO_JWT_SECRET=$(openssl rand -hex 64)
    REGISTRY_RANDOM_SECRET=$(openssl rand -hex 32)

    log_success "Secrets generated"
}

# Create installation directory
create_install_dir() {
    log_info "Creating installation directory..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Directory $INSTALL_DIR already exists"
        read -p "Overwrite? [y/N]: " OVERWRITE
        if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
            log_error "Installation cancelled"
            exit 1
        fi
        rm -rf "$INSTALL_DIR"
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    log_success "Installation directory created: $INSTALL_DIR"
}

# Download and process templates
download_templates() {
    log_info "Downloading configuration templates..."

    # curl supports file://, http://, and https:// URLs
    if command -v curl &> /dev/null; then
        curl -fsSL "$TEMPLATES_URL/docker-compose.yml" -o docker-compose.yml.template
        curl -fsSL "$TEMPLATES_URL/Caddyfile.template" -o Caddyfile.template
    else
        log_error "curl not found"
        exit 1
    fi

    log_success "Templates downloaded"
}

# Process templates with variable substitution
process_templates() {
    log_info "Processing templates..."
    
    GENERATION_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    # Process docker-compose.yml
    sed -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{PROTOCOL}}|${PROTOCOL}|g" \
        -e "s|{{WS_PROTOCOL}}|${WS_PROTOCOL}|g" \
        -e "s|{{AUTH_TYPE}}|${AUTH_TYPE}|g" \
        -e "s|{{ORG_NAME}}|${ORG_NAME}|g" \
        -e "s|{{ORG_DISPLAY_NAME}}|${ORG_DISPLAY_NAME}|g" \
        docker-compose.yml.template > docker-compose.yml
    
    # Process Caddyfile
    # Add http:// prefix for localhost to disable automatic HTTPS
    if [[ "$DOMAIN" == "localhost" || "$DOMAIN" == "127.0.0.1" ]]; then
        CADDY_DOMAIN="http://${DOMAIN}"
    else
        CADDY_DOMAIN="${DOMAIN}"
    fi

    sed -e "s|{{DOMAIN}}|${CADDY_DOMAIN}|g" \
        -e "s|{{ADMIN_EMAIL}}|${ADMIN_EMAIL}|g" \
        Caddyfile.template > Caddyfile
    
    # Create .env file
    cat > .env <<EOF
# Floww Configuration
# Generated: ${GENERATION_DATE}

# Domain and Protocol
DOMAIN=${DOMAIN}
PROTOCOL=${PROTOCOL}
WS_PROTOCOL=${WS_PROTOCOL}

# Authentication (password-based for self-hosting)
AUTH_TYPE=${AUTH_TYPE}

# Organization
ORG_NAME=${ORG_NAME}
ORG_DISPLAY_NAME=${ORG_DISPLAY_NAME}

# Security Secrets
DB_PASSWORD=${DB_PASSWORD}
CENTRIFUGO_API_KEY=${CENTRIFUGO_API_KEY}
SESSION_SECRET_KEY=${SESSION_SECRET_KEY}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
WORKFLOW_JWT_SECRET=${WORKFLOW_JWT_SECRET}
CENTRIFUGO_JWT_SECRET=${CENTRIFUGO_JWT_SECRET}
REGISTRY_RANDOM_SECRET=${REGISTRY_RANDOM_SECRET}

# Docker Registry (Optional)
DOCKER_REGISTRY_USER=${DOCKER_REGISTRY_USER}
DOCKER_REGISTRY_PASSWORD=${DOCKER_REGISTRY_PASSWORD}

# Admin
ADMIN_EMAIL=${ADMIN_EMAIL}
EOF
    
    # Create logs directory for Caddy
    mkdir -p logs
    
    # Clean up templates
    rm -f docker-compose.yml.template Caddyfile.template
    
    log_success "Configuration files created"
}

# Start services
start_services() {
    log_info "Starting Floww services..."
    echo ""
    
    docker compose pull
    docker compose up -d
    
    log_success "Services started"
}

# Wait for services to be healthy
wait_for_services() {
    log_info "Waiting for services to become healthy..."
    echo ""
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker compose ps | grep -q "unhealthy"; then
            echo -n "."
            sleep 2
            attempt=$((attempt + 1))
        else
            # Check if backend is responding
            if docker compose exec -T backend python3 -c "import requests; requests.get('http://localhost:8000/api/health', timeout=2).raise_for_status()" 2>/dev/null; then
                echo ""
                log_success "All services are healthy"
                return 0
            fi
            echo -n "."
            sleep 2
            attempt=$((attempt + 1))
        fi
    done
    
    echo ""
    log_warning "Services are taking longer than expected to start"
    log_info "Check logs with: docker compose logs -f"
}

# Print success message
print_success() {
    echo ""
    log_success "Floww Installation Complete!"
    echo ""
    echo "📂 Installation: $INSTALL_DIR"
    echo ""

    if [[ "$DOMAIN" == "localhost" || "$DOMAIN" == "127.0.0.1" ]]; then
        PROTOCOL="http"
        WS_PROTOCOL="ws"
    else
        PROTOCOL="https"
        WS_PROTOCOL="wss"
    fi

    echo "🌐 Access URLs:"
    echo "  Dashboard:  ${PROTOCOL}://${DOMAIN}"
    echo "  API:        ${PROTOCOL}://${DOMAIN}/api"
    echo "  WebSocket:  ${WS_PROTOCOL}://${DOMAIN}/ws"
    echo ""
    echo "💡 You'll create your admin account on first visit"
    echo ""

    echo "🛠️ Commands:"
    echo "  Start:   cd $INSTALL_DIR && docker compose up -d"
    echo "  Logs:    docker compose logs -f"
    echo "  Stop:    docker compose down"
    echo "  Update:  docker compose pull && docker compose up -d"
    echo ""
}

# Main installation flow
main() {
    print_banner
    check_prerequisites
    interactive_setup
    generate_secrets
    create_install_dir
    download_templates
    process_templates
    print_success
}

# Run main installation
main