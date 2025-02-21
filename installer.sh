#!/usr/bin/env bash 
set -e

#####################################
# Function: Kill any process holding the dpkg/apt locks
#####################################
kill_locks() {
    LOCKS=(
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
    )
    for LOCK in "${LOCKS[@]}"; do
        if sudo fuser "$LOCK" > /dev/null 2>&1; then
            PID=$(sudo fuser "$LOCK" 2>/dev/null)
            echo "Lock file $LOCK is held by process $PID, killing it..."
            sudo kill -9 $PID
            # Give the system a moment to release the lock
            sleep 2
        fi
    done
}

#####################################
# Attempt to fix any dpkg issues before proceeding
#####################################
fix_dpkg() {
    # Run the kill locks function first
    kill_locks

    # Try to reconfigure any interrupted packages
    sudo dpkg --configure -a || true
}

if dpkg --configure -a 2>&1 | grep -q "dpkg: error"; then
  sudo rm /var/lib/dpkg/updates/*
  sudo dpkg --configure -a
fi
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
# Fix potential dpkg/apt lock issues  #
#####################################
fix_dpkg

#####################################
# Update and Upgrade the System     #
#####################################
sudo apt-get update -q
# Uncomment the next line if you want to run a full upgrade:
# sudo apt-get upgrade "${APT_OPTIONS[@]}"

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

# Optional: Enable debugging (uncomment if needed)
# exp_internal 1

# Disable timeout so we wait indefinitely
set timeout -1

# Get the Node ID from the first argument
set nexus_node_id [lindex $argv 0]

# Start the Nexus installer
spawn ./nexus_installer.sh

# Keep matching prompts until the installer finishes
expect {
    # Handle "Press Enter to continue" prompt
    -re {Press\s+Enter\s+to\s+continue} {
        send "\r"
        exp_continue
    }
    
    # Handle the menu prompt that includes the earning option
    -re {\[2\].*start\s+earning} {
        send "2\r"
        exp_continue
    }
    
    # When the installer prints "Please enter your node ID:"
    -re {Please\s+enter\s+your\s+node\s+ID:} {
        send -- "$nexus_node_id\r"
        exp_continue
    }
    
    eof
}
EOF

chmod +x auto_nexus.exp

#####################################
# Run the Expect script
#####################################
./auto_nexus.exp "$NEXUS_NODE_ID"
