"""
ElasticGraph MCP Server
"""

import subprocess

from mcp.server.fastmcp import FastMCP
from mcp.shared.exceptions import McpError

from mcp_elasticgraph.errors import create_command_error
from mcp_elasticgraph.helpers import (
    GRAPHQL_SCHEMA_FILENAME,
    find_graphql_schema,
    run_command,
)

ResponseDict = dict[str, str | dict | bool]

# Initialize MCP server
instructions = """
ElasticGraph MCP Server provides tools and resources for working with ElasticGraph projects.

ElasticGraph is an open-source framework for building scalable search applications powered by GraphQL and
Elasticsearch / OpenSearch.

Available Resources:
- usage://commands: Common ElasticGraph commands and examples
- docs://links: Documentation, API reference, and guides
- schema://graphql: Current project's GraphQL schema

Available Tools:
- is_elasticgraph_project: Validate if current directory is an ElasticGraph project

For detailed command usage and examples, check the usage://commands resource.
For documentation and guides, check the docs://links resource.
""".strip()

mcp = FastMCP("mcp_elasticgraph", instructions=instructions)


# Resources
@mcp.resource("usage://commands")
def get_common_commands() -> ResponseDict:
    """
    Lists common ElasticGraph commands grouped by category.
    """
    commands = [
        {
            "command": "gem exec elasticgraph new PROJECT_NAME",
            "description": "Create a new ElasticGraph project in a new PROJECT_NAME directory",
            "example": "gem exec elasticgraph new my_project",
        },
        {
            "command": "bundle exec rake boot_locally",
            "description": "Start ElasticGraph for development, requires Docker",
            "example": "cd my_project && bundle exec rake boot_locally",
        },
        {
            "command": "bundle exec rake schema_artifacts:dump",
            "description": "Validate and dump the Ruby schema definition into schema.graphql",
            "example": "cd my_project && bundle exec rake schema_artifacts:dump",
        },
        {
            "command": "bundle exec rake -T",
            "description": "List available rake tasks with descriptions",
            "example": "cd my_project && bundle exec rake -T",
        },
    ]

    return {
        "status": "success",
        "message": "Successfully retrieved common ElasticGraph commands",
        "commands": commands,
    }


@mcp.resource("docs://links")
def get_documentation_links() -> ResponseDict:
    """
    Get links to ElasticGraph documentation and resources.
    """
    links = {
        "homepage": {"url": "https://block.github.io/elasticgraph/", "description": "ElasticGraph official website"},
        "query_api": {
            "url": "https://block.github.io/elasticgraph/query-api/",
            "description": "ElasticGraph Query API",
        },
        "guide": {
            "url": "https://block.github.io/elasticgraph/getting-started/",
            "description": "Getting Started with ElasticGraph guide",
        },
    }

    return {"status": "success", "message": "Successfully retrieved documentation links", "links": links}


@mcp.resource("schema://graphql")
def get_graphql_schema() -> ResponseDict:
    """
    Get the current GraphQL schema from the ElasticGraph project.
    Must be run from within an ElasticGraph project directory.
    """
    try:
        # Find the schema file
        schema_path = find_graphql_schema()

        # Read the schema file
        with open(schema_path, encoding="utf-8") as f:
            schema_content = f.read()

        return {
            "status": "success",
            "message": f"Successfully retrieved {GRAPHQL_SCHEMA_FILENAME}",
            "schema_path": schema_path,
            "schema": schema_content,
            "mime_type": "application/graphql",
        }

    except McpError as e:
        return {
            "status": "error",
            "message": e.error.message,
            "details": e.error.data.get("details", ""),
            "hint": e.error.data.get("hint", ""),
        }
    except OSError as e:
        return {
            "status": "error",
            "message": f"Failed to read {GRAPHQL_SCHEMA_FILENAME}",
            "details": str(e),
            "hint": "Check file permissions and try again",
        }


# Tools
@mcp.tool()
def is_elasticgraph_project() -> dict[str, bool | str]:
    """
    Checks if the current directory is an ElasticGraph project by looking for
    elasticgraph gems in the Gemfile.

    Usage:
        is_elasticgraph_project
    """
    try:
        # Check if Gemfile exists
        gemfile_check = run_command(
            ["test", "-f", "Gemfile"],
            "Failed to check for Gemfile",
        )

        if gemfile_check.returncode != 0:
            return {
                "is_elasticgraph": False,
                "message": "No Gemfile found in current directory",
            }

        # Search for elasticgraph gems in Gemfile
        grep_result = run_command(
            ["grep", "-E", 'gem "elasticgraph', "Gemfile"],
            "Failed to search Gemfile",
        )

        return {
            "is_elasticgraph": grep_result.returncode == 0,
            "message": "ElasticGraph gems found in Gemfile"
            if grep_result.returncode == 0
            else "No ElasticGraph gems found in Gemfile",
        }

    except subprocess.SubprocessError as e:
        raise create_command_error(
            "Error checking for ElasticGraph project",
            error=e,
        ) from e
