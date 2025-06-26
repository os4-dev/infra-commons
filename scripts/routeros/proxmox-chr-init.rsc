# --------------------------------------------------------------------------
# Script:       Proxmox CHR First Boot Network Initialization
# Filename:     proxmox-chr-init.rsc
# Author:       os4-dev
# Version:      1.3
# Date:         2025-06-26
# --------------------------------------------------------------------------
#
# DESCRIPTION:
# This script is designed to run on the first boot of a MikroTik CHR
# instance deployed from a Proxmox template.
#
# The source CHR template is intentionally built with a single network
# interface. For security, this interface should be connected to an
# isolated, internal-only network in Proxmox to allow for safe initial
# configuration before exposing the router to other networks.
#
# THE PROBLEM:
# When a VM is cloned from a template in Proxmox, it receives a new,
# unique MAC address. RouterOS detects this as a new piece of hardware
# and creates a new default interface (e.g., ether2), leaving the
# original interface configuration from the template inactive. This
# breaks network connectivity.
#
# THE SOLUTION:
# This script identifies the actual physical interface (assumed to be
# 'ether1'), renames it, and applies the correct management IP address.
# This ensures predictable network access immediately after deployment.
#
# USAGE:
# 1. Customize the variables in the "USER-DEFINED PARAMETERS" section below.
# 2. Upload this script to the CHR template's file system.
# 3. Add the script and a scheduler entry to run it on boot.
#
# LICENSE:
# This project is licensed under the Apache License, Version 2.0.
# See the LICENSE file for details.


# ==========================================================================
# SCRIPT LOGIC STARTS HERE
# ==========================================================================

# :log info "Running initial network configuration script...";
#
# /interface ethernet set [find default-name=ether1] name=$mgmtInterfaceName;
# /ip address add address=$mgmtIP interface=$mgmtInterfaceName;
#
# :log info "Network configuration applied. Interface '$mgmtInterfaceName' is set with IP '$mgmtIP'.";
# LICENSE:
# This project is licensed under the Apache License, Version 2.0.
# See the LICENSE file for details.
#

# ==========================================================================
# SCRIPT LOGIC STARTS HERE
# ==========================================================================

/system script add name="first-boot-setup" owner=admin policy=read,write,reboot,test source={
# === CHR Minimalist First Boot Interface Setup ===
# This script runs on the first boot of a clone with a single NIC.
# It finds the first (and only) ethernet interface, renames it,
# and binds the existing management IP address to it.
# It finishes by removing its scheduler and itself, then rebooting.

:log info "--- Starting First Boot Interface Setup Script ---";

# ==========================================================================
# USER-DEFINED PARAMETERS
# ---
# Please replace the placeholder values below with your actual network
# configuration.
# ==========================================================================

# The desired static IP address and subnet for the management interface.
# Example: "192.168.88.1/24"
:local mgmtIP "CHANGE_ME_IP_ADDRESS/SUBNET";

# The descriptive name you want to assign to the management interface.
# Example: "ether1-mgmt" or "WAN"
:local mgmtInterfaceName "CHANGE_ME_INTERFACE_NAME";

# Use the reliable two-step method to get the interface's internal ID and name
:local firstEthId [/interface ethernet find];
:local firstEthName [/interface ethernet get $firstEthId name];

# Check if an interface was found
:if ([:len $firstEthId] > 0) do={
    :log info "Found first ethernet interface: '$firstEthName'. Reconfiguring for management...";

    # Rename the found interface for clarity
    /interface set $firstEthId name=$mgmtInterfaceName;

    # Find the existing IP Address entry and set its interface to the one we just found and renamed
    /ip address set [find address=$mgmtIP] interface=$mgmtInterfaceName;

    :log info "Successfully bound IP $mgmtIP to interface '$mgmtInterfaceName'.";
} else {
    :log error "No ethernet interface found! Manual configuration required.";
}

# --- Cleanup and Reboot Sequence ---
:log info "Initial configuration complete. Proceeding with cleanup and reboot.";

# Remove the scheduler task that ran this script
/system scheduler remove [find name="run-init-script"];
:log info "Startup scheduler task 'run-init-script' has been removed.";

# Remove this script itself to keep the system clean
# Note: The script will continue to run from memory until it finishes.
/system script remove [find name=$name];
:log info "Self-destruct complete: Script '$name' has been removed.";

# Add a short delay to ensure logs are committed before reboot
:delay 2s;

# Reboot the device
:log info "Initiating reboot in 3.. 2.. 1..";
/system reboot;
}

/system scheduler add name="run-init-script" on-event="/system script run first-boot-setup" start-time=startup
