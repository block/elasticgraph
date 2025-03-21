"""
ElasticGraph helper functions for command execution and version management.

This module provides utility functions for:
- Running shell commands
- Version checking and management
- CLI help parsing
- Project validation
- Docker validation
"""

import os
import subprocess

import httpx

from elasticgraph_mcp.errors import create_command_error, create_not_in_project_error

# Constants
MIN_RUBY_VERSION = "3.2.0"
GRAPHQL_SCHEMA_FILENAME = "schema.graphql"
API_DOCS_URL = "https://block.github.io/elasticgraph/llms-full.txt"

# Common locations for the schema file relative to project root
COMMON_SCHEMA_PATHS = [
    f"config/schema/artifacts/{GRAPHQL_SCHEMA_FILENAME}",
]


# Cache for API docs content
_api_docs_cache = None


async def fetch_api_docs() -> str | None:
    """
    Fetch the ElasticGraph API docs with caching.
    Returns None if fetch fails.
    """
    global _api_docs_cache

    if _api_docs_cache is not None:
        return _api_docs_cache

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(API_DOCS_URL, timeout=10.0)
            response.raise_for_status()
            _api_docs_cache = response.text
            return _api_docs_cache
    except (httpx.HTTPError, httpx.ReadTimeout):
        return None


def run_command(command: list[str], error_message: str) -> subprocess.CompletedProcess:
    """
    Run a shell command and handle common error cases.

    Args:
        command: List of command parts to execute
        error_message: Human-readable error message if command fails

    Returns:
        CompletedProcess instance with command output

    Raises:
        McpError: If command execution fails
    """
    try:
        result = subprocess.run(command, capture_output=True, text=True)
        return result
    except subprocess.SubprocessError as e:
        raise create_command_error(error_message, error=e) from e


def check_elasticgraph_directory() -> None:
    """
    Check if current directory is an ElasticGraph project and raise if not.

    Raises:
        McpError: If not in an ElasticGraph project directory
    """
    try:
        # Check if Gemfile exists
        gemfile_check = run_command(
            ["test", "-f", "Gemfile"],
            "Failed to check for Gemfile",
        )

        if gemfile_check.returncode != 0:
            raise create_not_in_project_error("No Gemfile found in current directory")

        # Search for elasticgraph gems in Gemfile
        grep_result = run_command(
            ["grep", "-E", 'gem "elasticgraph', "Gemfile"],
            "Failed to search Gemfile",
        )

        if grep_result.returncode != 0:
            raise create_not_in_project_error("No ElasticGraph gems found in Gemfile")

    except subprocess.SubprocessError as e:
        raise create_command_error(
            "Error checking for ElasticGraph project",
            error=e,
        ) from e


def find_graphql_schema() -> str:
    """
    Find the GraphQL schema file in an ElasticGraph project.
    Checks common locations and searches for the file if not found.

    Returns:
        str: Path to the schema file

    Raises:
        McpError: If schema file cannot be found or if not in an ElasticGraph project
    """
    # First verify we're in an ElasticGraph project
    check_elasticgraph_directory()

    # Check common locations first
    for path in COMMON_SCHEMA_PATHS:
        if os.path.isfile(path):
            return path

    # If not found in common locations, search for it
    try:
        find_result = run_command(
            ["find", ".", "-name", GRAPHQL_SCHEMA_FILENAME],
            "Failed to search for schema file",
        )

        if find_result.returncode == 0 and find_result.stdout.strip():
            # Return the first found schema file
            schema_path = find_result.stdout.strip().split("\n")[0]
            if os.path.isfile(schema_path):
                # Convert path to use forward slashes and strip leading ./
                schema_path = schema_path.replace("\\", "/")
                if schema_path.startswith("./"):
                    schema_path = schema_path[2:]
                return schema_path

        raise create_command_error(
            f"{GRAPHQL_SCHEMA_FILENAME} not found",
            data={
                "hint": f"Make sure {GRAPHQL_SCHEMA_FILENAME} exists in your project",
                "details": "Searched common locations and performed file search",
            },
        )

    except subprocess.SubprocessError as e:
        raise create_command_error(
            "Error searching for GraphQL schema file",
            error=e,
        ) from e
