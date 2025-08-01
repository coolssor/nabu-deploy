#!/bin/bash
set -e

# Require root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m✖ This script must be run as root. Try: sudo ./uninstall-nabu.sh\e[0m"
    exit 1
fi

# Colors
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

echo -e "${BLUE}==> Starting Nabu Uninstaller...${RESET}"

function status() {
    echo -e "${GREEN}✔ $1${RESET}"
}

function error_exit() {
    echo -e "${RED}✖ $1${RESET}"
    exit 1
}

# Stop and remove known containers
containers=(open-webui ollama mcpo tts)

echo -e "${BLUE}Stopping and removing Nabu containers...${RESET}"
for cname in "${containers[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
        docker rm -f "$cname" && status "Removed container $cname"
    else
        echo "Container $cname does not exist."
    fi
done

# Remove Docker network if it exists
if docker network ls --format '{{.Name}}' | grep -q "^nabu$"; then
    docker network rm nabu && status "Removed Docker network 'nabu'"
else
    echo "Docker network 'nabu' does not exist."
fi

# Remove installed files and directories
echo -e "${BLUE}Removing configuration files and binaries...${RESET}"
rm -f /bin/nabu && status "Removed /bin/nabu"
rm -rf /etc/nabu && status "Removed /etc/nabu"

echo -e "${GREEN}✅ Nabu has been successfully uninstalled!${RESET}"
