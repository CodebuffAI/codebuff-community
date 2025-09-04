# Python CLI Template

A minimal Python CLI application template with modern Python features and type hints.

## Clone this template

```bash
# Create a new project using this template
codebuff --create python-cli my-app
```

## Getting Started

```bash
# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows use: .venv\Scripts\activate

# Install dependencies
pip install -e ".[dev]"

# Run in development mode
python -m cli

# Run type checker
mypy cli

# Build and install
pip install build
python -m build
pip install dist/*.whl
```

## Project Structure

- `cli/` - Source files
- `tests/` - Test files
- `pyproject.toml` - Project configuration
