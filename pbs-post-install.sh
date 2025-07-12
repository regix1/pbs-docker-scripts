#!/usr/bin/env bash

# Container-optimized PBS subscription nag removal script
# Based on the original post-install script

set -e

# Environment variables with defaults
PBS_ENTERPRISE=${PBS_ENTERPRISE:-"yes"}
PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION:-"yes"}
DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG:-"yes"}

echo "PBS Post-Install Configuration:"
echo "  PBS_ENTERPRISE=${PBS_ENTERPRISE}"
echo "  PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION}"
echo "  DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG}"

VERSION="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"

# Configure repositories
if [[ "${PBS_ENTERPRISE}" == "yes" ]]; then
    echo "Disabling enterprise repository..."
    echo "# Disabled by pbs-post-install.sh" > /etc/apt/sources.list.d/pbs-enterprise.list
    echo "# deb https://enterprise.proxmox.com/debian/pbs ${VERSION} pbs-enterprise" >> /etc/apt/sources.list.d/pbs-enterprise.list
fi

if [[ "${PBS_NO_SUBSCRIPTION}" == "yes" ]]; then
    echo "Enabling no-subscription repository..."
    echo "deb http://download.proxmox.com/debian/pbs ${VERSION} pbs-no-subscription" > /etc/apt/sources.list.d/pbs-install-repo.list
fi

# Disable subscription nag
if [[ "${DISABLE_SUBSCRIPTION_NAG}" == "yes" ]]; then
    echo "Disabling subscription nag..."
    
    # Wait for the file to exist (up to 60 seconds)
    for i in {1..30}; do
        if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
            echo "Found proxmoxlib.js, applying patch..."
            
            # Check if already patched
            if ! grep -q "NoMoreNagging" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then
                # Apply the patch
                sed -i.bak '/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
                echo "Subscription nag patch applied successfully"
            else
                echo "Subscription nag already patched"
            fi
            break
        fi
        echo "Waiting for proxmoxlib.js... (attempt $i/30)"
        sleep 2
    done
    
    if [ ! -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
        echo "WARNING: proxmoxlib.js not found after waiting 60 seconds"
    fi
    
    # Create apt configuration to handle future updates (container-friendly)
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/no-nag-script << 'INNER_EOF'
DPkg::Post-Invoke {
    "if dpkg -V proxmox-widget-toolkit 2>/dev/null | grep -q '/proxmoxlib\.js$'; then
        echo 'Re-applying subscription nag patch after package update...';
        sed -i '/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js || true;
    fi";
};
INNER_EOF
    echo "Created apt post-invoke hook for future updates"
fi

# Update package lists
echo "Updating package lists..."
apt-get update > /dev/null 2>&1

echo "PBS post-install configuration completed successfully"
