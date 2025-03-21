"""ElasticGraph MCP Server package."""

import argparse

from .server import mcp


def main() -> None:
    """Run the ElasticGraph MCP server."""
    parser = argparse.ArgumentParser(description="ElasticGraph MCP Server")
    parser.parse_args()
    mcp.run()


if __name__ == "__main__":
    main()
