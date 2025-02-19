#!/usr/bin/env bash
set -e

#####################################
# Define your Nexus node ID here    #
#####################################
NEXUS_NODE_ID=$(cat nexus_node_id.txt)

#####################################
# Prevent any interactive prompts   #
#####################################
export DEBIAN_FRONTEND=noninteractive

# Force dpkg to automatically accept new config files
APT_OPTIONS=(
    "-yq"
    "-o Dpkg::Options::=--force-confdef"
    "-o Dpkg::Options::=--force-confnew"
)

#####################################
# Update and Upgrade the System     #
#####################################
#sudo apt-get update -q
#sudo apt-get upgrade "${APT_OPTIONS[@]}"

#####################################
# Install Required Packages         #
#####################################
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y screen unzip expect
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential pkg-config libssl-dev git-all

#####################################
# Install Rust Non-Interactively    #
#####################################
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Load Rust environment and ensure cargo bin is in PATH
source "$HOME/.cargo/env"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

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
# Download & Make Nexus Installer   #
#####################################
curl -o nexus_installer.sh https://cli.nexus.xyz/
chmod +x nexus_installer.sh

# Replace the prompt for agreeing to terms with an automatic "Y" response
sed -i 's/read -p.*Do you agree.*/REPLY="Y"/' nexus_installer.sh

#####################################
# Remove Old Protobuf & Install v25.2
#####################################
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y protobuf-compiler || true
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
# Create an Expect script on the fly
#####################################
cat << 'EOF' > auto_nexus.exp
#!/usr/bin/expect -f

# Turn on debugging (optional). Comment out if too noisy:
# exp_internal 1

# Disable any timeout so we wait indefinitely
set timeout -1

# We pass the Node ID as the first argument to the script
set nexus_node_id [lindex $argv 0]

# Run the Nexus installer
spawn ./nexus_installer.sh

# Keep matching until the script finishes
expect {
    # Example: If the script prints "Press Enter to continue"
    -re {Press\s+Enter\s+to\s+continue} {
        send "\r"
        exp_continue
    }

    # Example: If the script says "Type 2 to start earning" or "start earning NEX"
    -re {start\s+earning.*} {
        send "2\r"
        exp_continue
    }

    # If the script prompts for "Enter your node ID" or "node ID:"
    -re {node\s+ID} {
        send "$nexus_node_id\r"
        exp_continue
    }

    # If we hit end-of-file (no more data), we're done
    eof
}
EOF

chmod +x auto_nexus.exp

#####################################
# Run the Expect script
#####################################
./auto_nexus.exp "$NEXUS_NODE_ID"
