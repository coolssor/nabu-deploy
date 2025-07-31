#!/bin/bash

set -e

# Require root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m✖ This script must be run as root. Try: sudo ./uninstall-nabu.sh\e[0m"
    exit 1
fi

# Colors for output
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

echo -e "${BLUE}==> Starting Nabu Installer...${RESET}"

# Function to show status messages
function status() {
    echo -e "${GREEN}✔ $1${RESET}"
}

function error_exit() {
    echo -e "${RED}✖ $1${RESET}"
    exit 1
}

# Check for required tools
command -v curl >/dev/null 2>&1 || error_exit "curl is not installed. Please install it and rerun the script."
command -v mkdir >/dev/null 2>&1 || error_exit "mkdir is missing, which is unusual. Aborting."

# Download nabu.sh to /bin/nabu
echo -e "${BLUE}Downloading nabu.sh...${RESET}"
curl -fsSL https://raw.githubusercontent.com/coolssor/nabu-deploy/refs/heads/main/nabu.sh -o /bin/nabu || error_exit "Failed to download nabu.sh"
chmod +x /bin/nabu
status "Installed /bin/nabu"

# Create /etc/nabu and subdirectories
echo -e "${BLUE}Setting up directories...${RESET}"
mkdir -p /etc/nabu/docker || error_exit "Failed to create /etc/nabu/docker"
status "Created /etc/nabu and /etc/nabu/docker"

# Download config.json
echo -e "${BLUE}Downloading config.json...${RESET}"
curl -fsSL https://raw.githubusercontent.com/coolssor/nabu-deploy/refs/heads/main/config.json -o /etc/nabu/config.json || error_exit "Failed to download config.json"
status "Installed /etc/nabu/config.json"

# Download Dockerfile
echo -e "${BLUE}Downloading mcpo.Dockerfile...${RESET}"
curl -fsSL https://raw.githubusercontent.com/coolssor/nabu-deploy/refs/heads/main/docker/mcpo.Dockerfile -o /etc/nabu/docker/mcpo.Dockerfile || error_exit "Failed to download Dockerfile"
status "Installed /etc/nabu/docker/mcpo.Dockerfile"

echo -e "${GREEN}✅ Nabu has been successfully installed!${RESET}"
