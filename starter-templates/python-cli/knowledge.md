# Python CLI Template Knowledge

## Project Overview

A minimal Python CLI application template with modern Python features and type hints.

## Key Features

- Uses virtual environments for isolation
- Type hints and mypy for static type checking
- Modern Python packaging with pyproject.toml
- Black for code formatting

## Verifying changes

After every change, run:

```bash
mypy cli && black --check cli
```

This will check for type errors and formatting issues.
