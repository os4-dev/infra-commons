# infra-commons

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

A collection of common, reusable scripts, configurations, Ansible roles, and OpenTofu modules for infrastructure setup and management. This repository aims to simplify repetitive tasks and promote consistency across projects.

## Purpose

The main goal of `infra-commons` is to provide a central place for well-tested and reusable infrastructure components, reducing boilerplate and accelerating the setup of new environments or projects.

## Contents

This repository currently includes:

* **Scripts (`scripts/`):** A collection of utility scripts for automating common infrastructure tasks, such as tool installation and virtual machine template creation.
* **OpenTofu Modules (`opentofu/modules/`):** Reusable modules for defining infrastructure resources. *(Work in Progress/Placeholder)*
* **Ansible Roles (`ansible/roles/`):** Reusable roles for configuration management. *(Work in Progress/Placeholder)*

## General Prerequisites

The specific prerequisites vary depending on the component (script, module, role) you intend to use. However, common requirements across the repository may include:

* **Shell:** A `bash` compatible shell for running shell scripts.
* **Python:** Python 3.x for any Python-based scripts or tools.
* **Ansible:** A working Ansible installation if you plan to use Ansible roles or playbooks.
* **OpenTofu/Terraform:** An OpenTofu or Terraform installation for IaC modules.
* **Standard Unix Utilities:** Tools like `curl`, `wget`, `gpg`, `git`, `jq`, etc., are often assumed to be available.

Please refer to the specific documentation for each component in our **[GitHub Wiki](https://github.com/os4-dev/infra-commons/wiki)** for detailed prerequisites.

## Usage

For detailed information on each script, module, or role, including its purpose, architecture, parameters, and usage examples, please consult our comprehensive **[GitHub Wiki](https://github.com/os4-dev/infra-commons/wiki)**.

## Future Plans

This repository is intended to grow. Future additions may include:

* More reusable Ansible roles for common server configurations.
* Additional OpenTofu modules for various cloud and on-premise resources.
* Examples demonstrating how to combine these components.
* Integration of linters (`shellcheck`, `ansible-lint`, `tflint`) and CI/CD pipelines for quality assurance.

## Contributing

Contributions are welcome! If you have suggestions for improvements or want to add new reusable components, please feel free to:

1.  Open an issue to discuss the proposed change.
2.  Fork the repository, make your changes, and submit a pull request.

Please ensure your contributions adhere to basic quality standards and include comprehensive documentation, preferably by adding or updating pages in the GitHub Wiki.

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.
