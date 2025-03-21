"""Tests for ElasticGraph helper functions."""

import os
from pathlib import Path

import pytest
from mcp.shared.exceptions import McpError

from elasticgraph_mcp.helpers import (
    COMMON_SCHEMA_PATHS,
    GRAPHQL_SCHEMA_FILENAME,
    find_graphql_schema,
)


class TestGraphQLSchema:
    """Tests for GraphQL schema functionality."""

    def test_find_schema_default_location(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test finding schema file in the default location."""
        os.chdir(mock_elasticgraph_project)
        schema_path = find_graphql_schema()
        expected_path = COMMON_SCHEMA_PATHS[0]  # First path is the default location
        assert schema_path == expected_path

    def test_find_schema_not_found(self, mock_elasticgraph_project: Path) -> None:
        """Test error when schema file is not found."""
        os.chdir(mock_elasticgraph_project)

        with pytest.raises(McpError) as exc_info:
            find_graphql_schema()

        assert GRAPHQL_SCHEMA_FILENAME in str(exc_info.value)
        assert "not found" in str(exc_info.value)

    def test_find_schema_outside_project(self, temp_dir: Path) -> None:
        """Test error when not in an ElasticGraph project."""
        os.chdir(temp_dir)

        with pytest.raises(McpError) as exc_info:
            find_graphql_schema()

        assert "No Gemfile found" in str(exc_info.value)
