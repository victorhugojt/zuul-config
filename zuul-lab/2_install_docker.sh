#!/bin/bash
# ===========================================================================
# Step 2: Install Docker & Docker Compose on GCP VM (Ubuntu)
# Run this ON the GCP VM
# ===========================================================================

echo "======================================================================"
echo "🐳 Installing Docker & Docker Compose"
echo "======================================================================"

# Update and install prerequisites
sudo apt-get update -y
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add current user to docker group (no sudo needed)
sudo usermod -aG docker ${USER}
newgrp docker

# Verify installationy
docker --version
docker compose version

echo ""
echo "======================================================================"
echo "✅ Docker installed successfully!"
echo "   You may need to logout/login for group changes to take effect"
echo "======================================================================"
