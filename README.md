# Yggdrasil Management Scripts

This repository contains two scripts for installing Yggdrasil and managing its peer configuration to ensure optimal performance.

## Scripts

### 1. `ygg_install.sh`
A script to install Yggdrasil and configure your system.

**Features:**
- Installs Yggdrasil and its dependencies.
- Adds the Yggdrasil repository and GPG key.

**Usage:**
```bash
chmod +x ygg_install.sh
sudo ./ygg_install.sh
```

### 2. `update_peers.sh`
A script to update the Yggdrasil peer list for optimal network connectivity.

**Features:**
- Fetches a list of available peers from a remote website.
- Measures the latency (ping) of each peer.
- Selects the top 3 peers with the lowest latency.
- Updates the `yggdrasil.conf` configuration file.
- Restarts the Yggdrasil service to apply the changes.

**Usage:**
```bash
chmod +x update_peers.sh
sudo ./update_peers.sh
