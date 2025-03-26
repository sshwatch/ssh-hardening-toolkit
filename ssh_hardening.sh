#!/bin/bash

# Interactive SSH Configuration Hardening Script
# Version 3.0
# Extended features with maintained simplicity

# Color codes
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m'

# Configuration files and directories
declare -r SSH_CONFIG="/etc/ssh/sshd_config"
declare -r BACKUP_DIR="/etc/ssh/backups"
declare -r BACKUP_CONFIG="${BACKUP_DIR}/sshd_config.backup_$(date +%Y%m%d_%H%M%S)"
declare -r LOG_FILE="/var/log/ssh_hardening.log"
declare -r ALLOWED_USERS_FILE="/etc/ssh/allowed_users"
declare -r SSH_KEYS_DIR="/etc/ssh/authorized_keys"

# Basic security settings
declare -A BASIC_SETTINGS=(
    ["Port"]="2222:Change default SSH port"
    ["PermitRootLogin"]="no:Disable direct root login"
    ["MaxAuthTries"]="3:Limit authentication attempts"
    ["PermitEmptyPasswords"]="no:Prevent empty password logins"
    ["PasswordAuthentication"]="no:Force key-based authentication"
)

# Advanced security settings
declare -A ADVANCED_SETTINGS=(
    ["X11Forwarding"]="no:Disable X11 forwarding"
    ["AllowTcpForwarding"]="no:Disable TCP forwarding"
    ["LoginGraceTime"]="60:Set login grace time"
    ["ClientAliveInterval"]="300:Set client alive interval"
    ["ClientAliveCountMax"]="2:Set maximum client alive count"
)

# Encryption settings
declare -A ENCRYPTION_SETTINGS=(
    ["Ciphers"]="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com:Modern encryption"
    ["KexAlgorithms"]="curve25519-sha256@libssh.org:Secure key exchange"
    ["MACs"]="hmac-sha2-512-etm@openssh.com:Strong authentication"
)

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    echo -e "${!level}[$level] $message${NC}"
}

# Check system requirements
check_system() {
    local required_packages=("openssh-server" "ufw" "fail2ban")
    
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            log_message "YELLOW" "$package is not installed. Installing..."
            apt-get install -y "$package"
        fi
    done
}

# Backup management
manage_backups() {
    mkdir -p "$BACKUP_DIR"
    
    # Keep only last 5 backups
    ls -t "$BACKUP_DIR" | tail -n +6 | xargs -I {} rm "$BACKUP_DIR/{}" 2>/dev/null
    
    if cp "$SSH_CONFIG" "$BACKUP_CONFIG"; then
        log_message "GREEN" "Backup created at $BACKUP_CONFIG"
    else
        log_message "RED" "Backup creation failed"
        exit 1
    fi
}

# Configure fail2ban
setup_fail2ban() {
    echo -e "\n${YELLOW}=== Fail2ban Configuration ===${NC}"
    read -rp "$(echo -e "${GREEN}Configure fail2ban for SSH protection? (y/n): ${NC}")" setup_fail2ban
    
    if [[ "$setup_fail2ban" =~ ^[Yy]$ ]]; then
        cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
        systemctl restart fail2ban
        log_message "GREEN" "Fail2ban configured for SSH protection"
    fi
}

# Configure firewall
setup_firewall() {
    echo -e "\n${YELLOW}=== Firewall Configuration ===${NC}"
    read -rp "$(echo -e "${GREEN}Configure UFW firewall for SSH? (y/n): ${NC}")" setup_ufw
    
    if [[ "$setup_ufw" =~ ^[Yy]$ ]]; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 2222/tcp
        ufw --force enable
        log_message "GREEN" "UFW firewall configured for SSH"
    fi
}

# Manage SSH keys
manage_ssh_keys() {
    echo -e "\n${YELLOW}=== SSH Key Management ===${NC}"
    read -rp "$(echo -e "${GREEN}Set up SSH keys for a user? (y/n): ${NC}")" setup_keys
    
    if [[ "$setup_keys" =~ ^[Yy]$ ]]; then
        read -rp "Enter username: " username
        
        if ! id "$username" &>/dev/null; then
            log_message "RED" "User $username does not exist"
            return 1
        fi
        
        local user_ssh_dir="/home/$username/.ssh"
        mkdir -p "$user_ssh_dir"
        chmod 700 "$user_ssh_dir"
        touch "$user_ssh_dir/authorized_keys"
        chmod 600 "$user_ssh_dir/authorized_keys"
        chown -R "$username:$username" "$user_ssh_dir"
        
        echo -e "${YELLOW}Please paste the public SSH key for $username:${NC}"
        read -r pubkey
        echo "$pubkey" >> "$user_ssh_dir/authorized_keys"
        log_message "GREEN" "SSH key added for $username"
    fi
}

# Configure allowed users
manage_allowed_users() {
    echo -e "\n${YELLOW}=== Allowed Users Configuration ===${NC}"
    read -rp "$(echo -e "${GREEN}Configure allowed SSH users? (y/n): ${NC}")" setup_users
    
    if [[ "$setup_users" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Enter allowed users (space-separated):${NC}"
        read -r allowed_users
        
        echo "AllowUsers $allowed_users" >> "$SSH_CONFIG"
        log_message "GREEN" "Configured allowed SSH users: $allowed_users"
    fi
}

# Apply security settings
apply_settings() {
    local -n settings=$1
    local section_name=$2
    
    echo -e "\n${YELLOW}=== $section_name Settings ===${NC}"
    for setting in "${!settings[@]}"; do
        configure_setting "$setting" "${settings[$setting]}"
    done
}

# Main configuration function
configure_ssh() {
    apply_settings BASIC_SETTINGS "Basic Security"
    
    read -rp "$(echo -e "${GREEN}Configure advanced security settings? (y/n): ${NC}")" advanced
    [[ "$advanced" =~ ^[Yy]$ ]] && apply_settings ADVANCED_SETTINGS "Advanced Security"
    
    read -rp "$(echo -e "${GREEN}Configure encryption settings? (y/n): ${NC}")" encryption
    [[ "$encryption" =~ ^[Yy]$ ]] && apply_settings ENCRYPTION_SETTINGS "Encryption"
}

# Verify and test configuration
verify_configuration() {
    if ! sshd -t; then
        log_message "RED" "SSH configuration test failed"
        offer_rollback
        return 1
    fi
    
    log_message "GREEN" "SSH configuration test passed"
    return 0
}

# Main execution
main() {
    clear
    echo -e "${YELLOW}SSH Hardening Script v3.0${NC}"
    echo -e "${BLUE}======================${NC}"
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_message "RED" "This script must be run as root"
        exit 1
    fi
    
    # Main menu
    PS3="Select an option (1-8): "
    options=("Check System Requirements" 
             "Configure SSH Security" 
             "Manage SSH Keys" 
             "Configure Firewall" 
             "Setup Fail2ban" 
             "Manage Allowed Users"
             "Verify Configuration"
             "Exit")
    
    select opt in "${options[@]}"; do
        case $opt in
            "Check System Requirements")
                check_system
                ;;
            "Configure SSH Security")
                manage_backups
                configure_ssh
                ;;
            "Manage SSH Keys")
                manage_ssh_keys
                ;;
            "Configure Firewall")
                setup_firewall
                ;;
            "Setup Fail2ban")
                setup_fail2ban
                ;;
            "Manage Allowed Users")
                manage_allowed_users
                ;;
            "Verify Configuration")
                verify_configuration
                ;;
            "Exit")
                break
                ;;
            *) 
                echo "Invalid option"
                ;;
        esac
    done
    
    # Final steps
    if verify_configuration; then
        read -rp "$(echo -e "${GREEN}Restart SSH service now? (y/n): ${NC}")" restart
        [[ "$restart" =~ ^[Yy]$ ]] && systemctl restart sshd
    fi
    
    log_message "GREEN" "SSH hardening completed"
    echo -e "${YELLOW}Remember to test SSH access before closing this session${NC}"
}

# Run the script
main
