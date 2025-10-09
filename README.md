# caffeine

[![Test](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test.yml/badge.svg)](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?style=for-the-badge&logo=gleam&logoColor=black)](https://gleam.run/)

<div align="center">
<img src="images/caffeine_icon.png" alt="Caffeine Icon" width="250" height="250">
</div>

Caffeine is a compiler for generating reliability artifacts from service expectation definitions.

***

## Installation

**We recommend using within a CICD pipeline.**

Within a GitHub Actions workflow, you can use the following action:
```bash
- name: Caffeine Language GitHub Action
  uses: Brickell-Research/caffeine_lang_github_action@vmain
```

[See the action in the Github Actions Marketplace](https://github.com/marketplace/actions/caffeine-language-github-action).

***

## Architecture & RFCs

For detailed architectural decisions and design proposals, see our [RFCs directory](rfcs/):

- [RFC 001: Extensible Architecture](rfcs/001_Extensible_Architecture.md) - Core architectural principles and design patterns
- [RFC 002: Caffeine Query Language](rfcs/002_Caffeine_Query_Language.md) - The Caffeine Query Language (CQL)
***

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

