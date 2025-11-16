#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

#===============================================================================
# Automatic Swap Configuration
#===============================================================================

# Configure a swap file with the same size as physical RAM
auto_swap_setup() {
    local swap_file="/swapfile"
    local ram_kb
    
    echo "Getting physical RAM size..."
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    local ram_bytes=$((ram_kb * 1024))
    local ram_human
    ram_human=$(numfmt --to=iec --suffix=B "${ram_bytes}")
    echo "Detected physical RAM size: $ram_human"

    local current_swap_bytes=0
    if [ -f "$swap_file" ]; then
        # Get current swap file size, default to 0 on error
        current_swap_bytes=$(sudo stat -c%s "$swap_file" 2>/dev/null || echo 0)
    fi

    # Compare sizes (allow 1% tolerance)
    local tolerance=$((ram_bytes / 100))
    local diff=$((ram_bytes - current_swap_bytes))
    [ $diff -lt 0 ] && diff=$((diff * -1)) # absolute value

    if [ "$diff" -lt "$tolerance" ]; then
        echo "Swap file $swap_file already exists and has the correct size ($ram_human)."
        if ! grep -q "^$swap_file" /proc/swaps; then
            echo "Warning: Swap file is not active. Activating..."
            sudo swapon "$swap_file"
        fi
        echo "Swap is already configured correctly."
        return 0
    fi

    # --- Swap is NOT correctly configured, check space BEFORE recreating ---
    
    echo "Checking available disk space before recreation..."
    local total_space avail_space
    # Get total and available space in bytes (-B1) for the root filesystem
    read total_space avail_space < <(df -B1 --output=size,avail / | tail -n 1)

    echo "Checking available disk space before recreation..."
    local avail_space
    # Get available space in bytes (-B1) for the root filesystem
    avail_space=$(df -B1 --output=avail / | tail -n 1 | sed 's/ //g')

    # Define the minimum required free space: 30 GiB (30 * 1024^3)
    local min_free_space_bytes=$((30 * 1024 * 1024 * 1024))
    local min_free_space_human="30GiB"
    
    # Calculate projected free space: (current free) + (space from old swap) - (space for new swap)
    local projected_avail_space=$((avail_space + current_swap_bytes - ram_bytes))
    
    if [ "$projected_avail_space" -lt "$min_free_space_bytes" ]; then
        local projected_avail_human
        projected_avail_human=$(numfmt --to=iec --suffix=B "${projected_avail_space}")

        echo "Error: Not enough disk space to create new swap file." >&2
        echo "Required minimum free space after operation: $min_free_space_human" >&2
        echo "Creating a $ram_human swap file would only leave $projected_avail_human free." >&2
        echo "Aborting swap file creation." >&2
        return 0 # Abort the function
    fi
    echo "Disk space check passed. Proceeding with swap recreation."

    # --- Proceed with recreation ---

    if [ "$current_swap_bytes" -gt 0 ]; then
        local current_swap_human
        current_swap_human=$(numfmt --to=iec --suffix=B "${current_swap_bytes}")
        echo "Warning: Swap file size ($current_swap_human) does not match RAM ($ram_human)."
    else
        echo "Info: /swapfile not found."
    fi
    
    echo "Recreating $swap_file ..."

    if grep -q "^$swap_file" /proc/swaps; then
        echo "Deactivating (swapoff) existing $swap_file..."
        sudo swapoff "$swap_file"
    fi

    if [ -f "$swap_file" ]; then
        echo "Deleting old $swap_file..."
        sudo rm -f "$swap_file"
    fi

    echo "Allocating new $ram_human swap file (using fallocate)..."
    if ! sudo fallocate -l "$ram_bytes" "$swap_file"; then
        echo "Warning: fallocate failed. Falling back to dd (this may take a while)..."
        sudo dd if=/dev/zero of="$swap_file" bs=1K count="$ram_kb" status=progress
    else
        echo "File allocation successful."
    fi

    echo "Setting permissions (chmod 600)..."
    sudo chmod 600 "$swap_file"

    echo "Formatting as swap (mkswap)..."
    sudo mkswap "$swap_file"

    echo "Activating new swap (swapon)..."
    sudo swapon "$swap_file"

    echo "Updating /etc/fstab for persistence..."
    
    # Remove any old /swapfile entries
    if grep -q "^$swap_file" /etc/fstab; then
        echo "Removing old swap entry from /etc/fstab..."
        sudo sed -i '\%^/swapfile%d' /etc/fstab
    fi
    
    # Add the new entry
    echo "Adding new swap entry to /etc/fstab..."
    # Correct path: /etc/fstab
    if ! echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null; then
        echo "Error: Failed to automatically update /etc/fstab." >&2
        echo "Warning: You may need to manually add '$swap_file none swap sw 0 0' to /etc/fstab." >&2
    else
        echo "/etc/fstab updated successfully."
    fi
}

# Main function
main() {
    # Ensure numfmt is installed (it's part of coreutils, but good to check)
    if ! command -v numfmt &> /dev/null; then
        echo "Installing coreutils (for numfmt)..."
        sudo apt-get update
        sudo apt-get install -y coreutils
    fi
    
    echo "Starting automatic swap file configuration..."
    
    auto_swap_setup
    
    echo "Swap configuration completed!"
}

# Execute main function
main