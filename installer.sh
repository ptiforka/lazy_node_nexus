#!/bin/bash
set -e

#####################################
# Define your Nexus node ID here    #
#####################################
NEXUS_NODE_ID=$(cat nexus_node_id.txt)

#####################################
# Prevent any interactive prompts   #
#####################################
export DEBIAN_FRONTEND=noninteractive

# Force dpkg to automatically accept new config files ONLY if no local modifications exist,
# and keep the local file otherwise.
APT_OPTIONS=(
    "-yq"
    "-o Dpkg::Options::=--force-confold"
)

#####################################
# Update and Upgrade the System     #
#####################################
sudo apt-get update -q
sudo apt-get upgrade "${APT_OPTIONS[@]}"

#####################################
# Install Required Packages         #
#####################################
sudo apt-get install "${APT_OPTIONS[@]}" \
    build-essential pkg-config libssl-dev git-all protobuf-compiler cargo screen unzip

#####################################
# Install Rust Non-Interactively    #
#####################################
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Load Rust environment and ensure cargo bin is in PATH
source "$HOME/.cargo/env"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Update Rust to the latest stable
rustup update

#####################################
# Reconfigure Swap (16G)            #
#####################################
if [ -f /swapfile ]; then
    sudo swapoff /swapfile
    sudo rm /swapfile
fi
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

#####################################
# Download and Modify Nexus Installer
# to Auto-Accept Beta Terms          #
#####################################
curl -o nexus_installer.sh https://cli.nexus.xyz/
chmod +x nexus_installer.sh

# Replace the prompt for agreeing to terms with an automatic "Y" response
sed -i 's/read -p.*Do you agree.*/REPLY="Y"/' nexus_installer.sh

#####################################
# Remove Old Protobuf & Install
# Specific Protoc Version (v25.2)   #
#####################################
sudo apt-get remove "${APT_OPTIONS[@]}" protobuf-compiler
curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v25.2/protoc-25.2-linux-x86_64.zip
unzip -o protoc-25.2-linux-x86_64.zip -d "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
protoc --version

#####################################
# Add Rust Target and Component     #
#####################################
rustup target add riscv32i-unknown-none-elf
rustup component add rust-src

#####################################
# Run Nexus Installer Non-Interactively
# - First prompt: "2" (start earning)
# - Second prompt: node ID
#####################################
echo -e "2\n${NEXUS_NODE_ID}\n" | ./nexus_installer.sh
