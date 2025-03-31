#!/bin/bash

# Installation script for Docker CI/CD automation

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Docker CI/CD Automation Setup${NC}"
echo "This script will set up the Docker CI/CD automation system."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI (gh) is not installed.${NC}"
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Installing GitHub CLI for Linux..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installing GitHub CLI for macOS..."
        brew install gh
    else
        echo -e "${RED}Unsupported OS. Please install GitHub CLI manually: https://github.com/cli/cli#installation${NC}"
        exit 1
    fi
fi

# Authenticate with GitHub
echo -e "${YELLOW}Authenticating with GitHub...${NC}"
gh auth status || gh auth login

# Get GitHub repository details
echo -e "${YELLOW}Please enter your GitHub username:${NC}"
read GITHUB_USERNAME
echo -e "${YELLOW}Please enter your GitHub repository name:${NC}"
read GITHUB_REPO

# Update wrapper script with correct GitHub repository details
echo "Updating wrapper script with your GitHub details..."
sed -i "s/YOUR_USERNAME/$GITHUB_USERNAME/g" scripts/docker-push-wrapper.sh
sed -i "s/YOUR_REPO/$GITHUB_REPO/g" scripts/docker-push-wrapper.sh

# Make wrapper script executable
chmod +x scripts/docker-push-wrapper.sh

# Install wrapper script
echo "Installing wrapper script..."
sudo cp scripts/docker-push-wrapper.sh /usr/local/bin/docker-push

# Set up GitHub repository secrets
echo -e "${YELLOW}Setting up Docker Hub credentials as GitHub secrets...${NC}"
echo "Please enter your Docker Hub username:"
read DOCKERHUB_USERNAME
echo "Please enter your Docker Hub token (will be hidden):"
read -s DOCKERHUB_TOKEN

# Set GitHub secrets
gh secret set DOCKERHUB_USERNAME --body "$DOCKERHUB_USERNAME" --repo "$GITHUB_USERNAME/$GITHUB_REPO"
gh secret set DOCKERHUB_TOKEN --body "$DOCKERHUB_TOKEN" --repo "$GITHUB_USERNAME/$GITHUB_REPO"

echo -e "${GREEN}Installation complete!${NC}"
echo "You can now use 'docker-push push yourusername/yourrepo:tag' to push images with security scanning."