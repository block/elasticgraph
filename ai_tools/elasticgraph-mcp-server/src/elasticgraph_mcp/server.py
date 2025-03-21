"""
ElasticGraph MCP Server
"""

import json
import subprocess

from mcp.server.fastmcp import FastMCP
from mcp.shared.exceptions import McpError

from elasticgraph_mcp.errors import create_command_error
from elasticgraph_mcp.helpers import (
    GRAPHQL_SCHEMA_FILENAME,
    fetch_api_docs,
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
- docs://api: Full ElasticGraph API documentation
- schema://graphql: Current project's GraphQL schema

Available Tools:
- is_elasticgraph_project: Validate if current directory is an ElasticGraph project

For detailed command usage and examples, use the usage://commands resource.
For documentation and guides, use the docs://links resource.
For complete ElasticGraph API reference, use the docs://api resource.
""".strip()

mcp = FastMCP("elasticgraph_mcp", instructions=instructions)


# Resources
@mcp.resource("docs://api")
async def get_api_docs() -> ResponseDict:
    """
    Get the full ElasticGraph API documentation in one file.
    Fetches from source: https://block.github.io/elasticgraph/llms-full.txt
    """
    try:
        docs = await fetch_api_docs()

        if docs is None:
            raise create_command_error(
                "Failed to fetch API documentation",
                data={
                    "hint": "Check your internet connection and try again",
                    "details": "Could not fetch documentation from remote server",
                },
            )

        return {"contents": [{"uri": "docs://api", "mimeType": "text/plain", "text": docs}]}
    except McpError:
        raise
    except Exception as e:
        raise create_command_error(
            "Failed to fetch API documentation",
            error=e,
            data={
                "hint": "Check your internet connection and try again",
                "details": "An unexpected error occurred while fetching documentation",
            },
        ) from e


@mcp.resource("usage://commands")
def get_common_commands() -> ResponseDict:
    """
    Lists common ElasticGraph commands grouped by category.
    """
    try:
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
            "contents": [
                {"uri": "usage://commands", "mimeType": "application/json", "text": json.dumps({"commands": commands})}
            ]
        }
    except Exception as e:
        raise create_command_error(
            "Failed to generate commands list",
            error=e,
            data={
                "hint": "This is an internal error, please report it",
                "details": "Error occurred while generating commands list",
            },
        ) from e


@mcp.resource("docs://links")
def get_documentation_links() -> ResponseDict:
    """
    Get links to ElasticGraph documentation and resources.
    """
    try:
        links = {
            "homepage": {
                "url": "https://block.github.io/elasticgraph/",
                "description": "ElasticGraph official website",
            },
            "query_api": {
                "url": "https://block.github.io/elasticgraph/query-api/",
                "description": "ElasticGraph Query API",
            },
            "guide": {
                "url": "https://block.github.io/elasticgraph/getting-started/",
                "description": "Getting Started with ElasticGraph guide",
            },
        }

        return {
            "contents": [{"uri": "docs://links", "mimeType": "application/json", "text": json.dumps({"links": links})}]
        }
    except Exception as e:
        raise create_command_error(
            "Failed to generate documentation links",
            error=e,
            data={
                "hint": "This is an internal error, please report it",
                "details": "Error occurred while generating documentation links",
            },
        ) from e


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

        return {"contents": [{"uri": "schema://graphql", "mimeType": "application/graphql", "text": schema_content}]}

    except McpError:
        raise
    except OSError as e:
        raise create_command_error(
            f"Failed to read {GRAPHQL_SCHEMA_FILENAME}",
            error=e,
            data={
                "hint": "Check file permissions and try again",
                "details": f"Error reading schema file: {str(e)}",
            },
        ) from e
    except Exception as e:
        raise create_command_error(
            "Failed to process GraphQL schema",
            error=e,
            data={
                "hint": "Make sure you are in an ElasticGraph project directory",
                "details": "An unexpected error occurred while processing the schema",
            },
        ) from e


# Tools
@mcp.tool()
def is_elasticgraph_project() -> dict[str, list]:
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
                "content": [
                    {
                        "type": "text",
                        "text": "No Gemfile found in current directory. This is not an ElasticGraph project.",
                    }
                ]
            }

        # Search for elasticgraph gems in Gemfile
        grep_result = run_command(
            ["grep", "-E", 'gem "elasticgraph', "Gemfile"],
            "Failed to search Gemfile",
        )

        is_eg_project = grep_result.returncode == 0
        message = (
            "This is an ElasticGraph project - found ElasticGraph gems in Gemfile."
            if is_eg_project
            else "This is not an ElasticGraph project - no ElasticGraph gems found in Gemfile."
        )

        return {"content": [{"type": "text", "text": message}]}

    except subprocess.SubprocessError as e:
        raise create_command_error(
            "Error checking for ElasticGraph project",
            error=e,
        ) from e
