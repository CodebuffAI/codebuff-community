"""A Python CLI application."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("cli")
except PackageNotFoundError:
    # Package not installed, fallback for development
    try:
        import toml  # type: ignore[import-untyped]

        __version__ = toml.load("pyproject.toml")["project"]["version"]
    except Exception:
        __version__ = "unknown"
