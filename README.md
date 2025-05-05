# infra-commons

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

A collection of common, reusable scripts, configurations, Ansible roles, and OpenTofu modules for infrastructure setup and management. This repository aims to simplify repetitive tasks and promote consistency across projects.

## Table of Contents

- [Purpose](#purpose)
- [Current Contents](#current-contents)
  - [Scripts](#scripts)
- [Usage](#usage)
  - [Prerequisites](#prerequisites)
  - [Running the Installation Scripts](#running-the-installation-scripts)
- [Future Plans](#future-plans)
- [Contributing](#contributing)
- [License](#license)

## Purpose

The main goal of `infra-commons` is to provide a central place for well-tested and reusable infrastructure components, reducing boilerplate and accelerating the setup of new environments or projects.

## Current Contents

Currently, this repository primarily contains utility scripts for setting up common Infrastructure as Code (IaC) tools.

### Scripts

Located in the `scripts/` directory:

- **`install_iac_tools.sh`**: The main script that orchestrates the installation of various tools. It likely calls other specific installation scripts.
- **`install_ansible.sh`**: Script specifically for installing Ansible and its dependencies.
- **`install_opentofu.sh`**: Script specifically for installing OpenTofu (or Terraform) and its dependencies.

*(Please update the descriptions above if the scripts function differently)*

## Usage

### Prerequisites

- A `bash` compatible shell.
- Standard Unix utilities (`curl` or `wget`, `gpg`, `lsb_release`, etc.).
- Operating System: Currently tested/developed primarily on **Debian/Ubuntu-based** Linux distributions. (Please update if other OS are supported).
- `sudo` privileges are required to install system packages.

### Running the Installation Scripts

1.  **Clone the repository (optional):**
    ```bash
    git clone [https://github.com/os4-dev/infra-commons.git](https://github.com/os4-dev/infra-commons.git)
    cd infra-commons/scripts
    ```

2.  **Download a specific script (if you don't want to clone):**
    ```bash
    # Example using curl for the main script
    curl -LO [https://raw.githubusercontent.com/os4-dev/infra-commons/main/scripts/install_iac_tools.sh](https://raw.githubusercontent.com/os4-dev/infra-commons/main/scripts/install_iac_tools.sh)
    chmod +x install_iac_tools.sh
    ```

3.  **Execute the script:**
    It's recommended to review scripts downloaded from the internet before executing them.
    ```bash
    # Run the main installer script
    sudo bash ./install_iac_tools.sh
    ```
    *(Adjust the command if the script requires specific arguments)*

## Future Plans

This repository is intended to grow. Future additions may include:

- Reusable Ansible roles for common tasks (e.g., setting up users, configuring firewalls, installing software).
- Reusable OpenTofu modules for creating infrastructure components (e.g., virtual machines, networks, storage).
- Examples demonstrating how to use the roles and modules.
- Linters (`shellcheck`, `ansible-lint`, `tflint`) and CI/CD integration for quality assurance.

## Contributing

Contributions are welcome! If you have suggestions for improvements or want to add new reusable components, please feel free to:

1.  Open an issue to discuss the proposed change.
2.  Fork the repository, make your changes, and submit a pull request.

Please ensure your contributions adhere to basic quality standards and include documentation where necessary.

## License

This project is licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

&nbsp;&nbsp;&nbsp;&nbsp;[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

The full text of the license can also be found in the [LICENSE](LICENSE) file in this repository.
