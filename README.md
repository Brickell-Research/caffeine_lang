# caffeine_lang

<div align="center">

<img src="images/temp_caffeine_icon.png" alt="Caffeine Icon" width="250" height="250">

[![Hex.pm](https://img.shields.io/hexpm/v/caffeine_lang?style=for-the-badge&logo=erlang&logoColor=white)](https://hex.pm/packages/caffeine_lang)
[![CI](https://img.shields.io/github/actions/workflow/status/Brickell-Research/caffeine_lang/test_caffeine.yml?style=for-the-badge&logo=github&label=tests)](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test_caffeine.yml)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?style=for-the-badge&logo=gleam&logoColor=black)](https://gleam.run/)

The pure compiler core for the [Caffeine](https://caffeine-lang.run) DSL — generates reliability SLOs (Terraform for Datadog, Honeycomb, Dynatrace, NewRelic) from service expectation definitions.

</div>

***

## Usage

### As a Gleam dependency

```toml
# gleam.toml
[dependencies]
caffeine_lang = ">= 5.0.11 and < 6.0.0"
```

```gleam
import caffeine_lang/compiler

let result = compiler.compile_from_strings(blueprints, expectations, output_path)
```

### In the browser

```javascript
import { compile_from_strings } from "./caffeine-browser.js";
const result = compile_from_strings(blueprintsJson, expectationsJson, "org/team/service.json");
```

## Looking for the CLI or LSP?

The installable binary (CLI + Language Server) lives in the [`caffeine`](https://github.com/Brickell-Research/caffeine) repo:

```bash
brew tap brickell-research/caffeine
brew install caffeine_lang
```

## Development

```bash
gleam test                     # Run tests (Erlang target)
gleam test --target javascript # Run tests (JavaScript target)
make ci                        # lint + build + test (both targets)
```

## Learn more

- [Website](https://caffeine-lang.run)
- [Hex package](https://hex.pm/packages/caffeine_lang)
- [CLI & LSP repo](https://github.com/Brickell-Research/caffeine)
