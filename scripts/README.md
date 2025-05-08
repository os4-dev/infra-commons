### `scripts/README.md` (English Version - For `scripts/` directory)

# Infrastructure Commons - Scripts

This directory contains scripts designed to automate the installation of common Infrastructure as Code (IaC) tools, related development utilities, and auxiliary infrastructure tools on Debian/Ubuntu-based systems.

## Scripts Overview

- **`install_iac_tools.sh`**:
  The main orchestration script for **IaC tools**. It prepares the system, installs dependencies, and calls other specific installation scripts for IaC tools (Ansible, OpenTofu). It can optionally install development tools based on command-line flags. Use this script as the primary entry point for setting up Ansible and OpenTofu.

- **`install_ansible.sh`**:
  Handles the specific steps for installing Ansible. Typically **not meant to be run directly**.

- **`install_opentofu.sh`**:
  Handles the specific steps for installing OpenTofu. Typically **not meant to be run directly**.

- **`install_dev_tools.sh`**:
  Installs common **development tools** useful when working with infrastructure code (e.g., `shellcheck`). Typically called by `install_iac_tools.sh` with `--dev` flags and **not meant to be run directly**.

- **`install_infra_utils.sh`**:  Installs various **auxiliary utilities** useful for general infrastructure work, interacting with virtualization platforms (like Proxmox indirectly), managing images, processing data, etc. This script is independent of `install_iac_tools.sh` and installs tools like `curl`, `wget`, `jq`, `qemu-utils` (safely checks on Proxmox), `pwgen`, `virt-what`, and optionally handles SSH key setup, `sshpass`, and Python tools (`proxmoxer`).

## Usage: `install_iac_tools.sh`

This is the primary script to execute for setting up tools.

**Prerequisites:**

- **Operating System:** Debian or Ubuntu based Linux distribution.
- **Shell:** `bash`.
- **Utilities:** Internet connection required for downloading packages. Core utilities like `lsb_release`, `curl`, `gpg`, `wget` will be installed by the script if missing (as part of `prepare_system`).
- **Permissions:** Root privileges are required. Run the script using `sudo`.

**Command:**

```bash
# Navigate to the scripts directory first if you cloned the repo
# cd /path/to/infra-commons/scripts

# Execute with sudo
sudo bash ./install_iac_tools.sh [OPTIONS]
```
**Options:**

-   `(no options)`: Installs the standard IaC tools (Ansible, OpenTofu) and essential dependencies.
-   `--dev`: Installs the standard IaC tools (Ansible, OpenTofu) AND common development tools (like `shellcheck`).
-   `--dev-only`: Installs ONLY the common development tools (like `shellcheck`), skipping Ansible, OpenTofu, and their primary dependencies.
-   `-h`, `--help`: Displays the help message and exits.

**Examples:**

1.  **Install only IaC tools (Ansible, OpenTofu):**
    ```bash
    sudo bash ./install_iac_tools.sh
    ```
2.  **Install IaC tools AND Development tools:**
    ```bash
    sudo bash ./install_iac_tools.sh --dev
    ```
3.  **Install ONLY Development tools:**
    ```bash
    sudo bash ./install_iac_tools.sh --dev-only
    ```

## How it Works

1.  The `install_iac_tools.sh` script first parses any command-line options (e.g., \`--dev\`, \`--dev-only\`, \`--help\`).
2.  It verifies it's running with root privileges (`sudo`).
3.  **If not using** \`--dev-only\`:
    * It calls `prepare_system()` to run `apt-get update` and install essential dependencies (`wget`, `curl`, `gpg`, etc.).
    * It determines the correct PPA codename for Ansible based on the OS.
    * It executes `install_ansible.sh` (passing the codename).
    * It executes `install_opentofu.sh`.
4.  **If** \`--dev\` **or** \`--dev-only\` **was specified:**
    * It executes `install_dev_tools.sh`. This script runs `apt-get update` again (which is safe) and then installs tools like `shellcheck`.
5.  Finally, it prints a summary of installed components.

## Usage: `install_infra_utils.sh`

This script installs auxiliary infrastructure utilities. It can be run independently.

**Prerequisites:**

* **Operating System:** Debian or Ubuntu based Linux distribution.
* **Shell:** `bash`.
* **Utilities:** Internet connection required for downloading packages. `sudo` is required for package installation if not run as root. Core utilities like `dpkg`, `apt`, `command`, `grep`, `tput` are expected to be present.
* **Permissions:** Root privileges might be required for installing packages. The script attempts to use `sudo` if run by a non-root user.

**Command:**

```bash
# Navigate to the scripts directory first if you cloned the repo
# cd /path/to/infra-commons/scripts
# Execute the script
bash ./install_infra_utils.sh [OPTIONS]
```
*Note: `sudo` might be needed internally by the script if run as a non-root user.*

**Options:**

* `(no options)`: Installs the core utilities (`wget`, `curl`, `jq`, `virt-what`, `pwgen`, checks/skips `qemu-utils` based on host type) and performs the SSH key check/generation prompt.
* `-h`, `--help`: Displays the help message and exits.
* `-l`, `--list-utils`: Lists all utilities that can be installed by this script and exits.
* `--no-ssh-keygen`: Skips the SSH key generation/check step.
* `--install-python`: Installs Python3, pip, and the 'proxmoxer' library.
* `--install-sshpass`: Installs 'sshpass' (use with caution).

**Examples:**

1.  **Install core utilities and check/generate SSH key:**
    ```bash
    bash ./install_infra_utils.sh
    ```
2.  **List available utilities:**
    ```bash
    bash ./install_infra_utils.sh --list-utils
    ```
3.  **Install core utilities, Python tools, but skip SSH key check:**
    ```bash
    bash ./install_infra_utils.sh --install-python --no-ssh-keygen
    ```

---

## Verification

After running the scripts, you can verify the installations using the following commands:

* `ansible --version` (if installed via `install_iac_tools.sh`)
* `tofu --version` (if installed via `install_iac_tools.sh`)
* `shellcheck --version` (if installed with `--dev` or `--dev-only` flags in `install_iac_tools.sh`)
* `jq --version` (if installed via `install_infra_utils.sh`)
* `qemu-img --version` (if `qemu-utils` was installed or if running on Proxmox)
* `pwgen --help` (if installed via `install_infra_utils.sh`)
* `virt-what --version` (if installed via `install_infra_utils.sh`)
