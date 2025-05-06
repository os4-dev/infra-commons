### `scripts/README.md` (English Version - For `scripts/` directory)

# Infrastructure Commons - Scripts

This directory contains scripts designed to automate the installation of common Infrastructure as Code (IaC) tools and related development utilities on Debian/Ubuntu-based systems.

## Scripts Overview

- **`install_iac_tools.sh`**:
  The main orchestration script. It prepares the system, installs dependencies, and calls other specific installation scripts for IaC tools (Ansible, OpenTofu). It can optionally install development tools based on command-line flags. Use this script as the primary entry point.

- **`install_ansible.sh`**:
  Handles the specific steps for installing Ansible, including adding the necessary PPA based on the OS codename (passed as an argument by `install_iac_tools.sh`). This script is typically **not meant to be run directly**.

- **`install_opentofu.sh`**:
  Handles the specific steps for downloading and installing OpenTofu from its official repository. This script is typically **not meant to be run directly**.

- **`install_dev_tools.sh`**:
  Installs common development tools useful when working with infrastructure code, such as linters. Currently includes:
    - `shellcheck` (for linting shell scripts)
  *This script is called by `install_iac_tools.sh` when the `--dev` or `--dev-only` flag is used and is generally **not meant to be run directly**.*

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

## Verification

After running the script, you can verify the installations using the following commands:

* `ansible --version` (if installed)
* `tofu --version` (if installed)
* `shellcheck --version` (if installed with \`--dev\` or \`--dev-only\`)
