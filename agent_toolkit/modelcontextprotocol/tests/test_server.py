"""Tests for ElasticGraph MCP server functionality."""

import os
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from mcp_elasticgraph.helpers import COMMON_SCHEMA_PATHS, GRAPHQL_SCHEMA_FILENAME
from mcp_elasticgraph.server import (
    get_graphql_schema,
    is_elasticgraph_project,
)


@pytest.fixture
def mock_project_checks():
    """Mock the project directory checks."""
    with patch("mcp_elasticgraph.helpers.run_command") as mock_run:
        # Mock successful Gemfile and elasticgraph checks
        mock_run.side_effect = [
            Mock(returncode=0),  # test -f Gemfile
            Mock(returncode=0),  # grep elasticgraph
        ]
        yield mock_run


class TestProjectDetection:
    """Tests for ElasticGraph project detection."""

    def test_valid_project(self, mock_elasticgraph_project: Path) -> None:
        """Test detecting a valid ElasticGraph project."""
        os.chdir(mock_elasticgraph_project)
        result = is_elasticgraph_project()

        assert result["is_elasticgraph"] is True
        assert "ElasticGraph gems found" in result["message"]

    def test_invalid_project(self, temp_dir: Path) -> None:
        """Test detecting an invalid project directory."""
        result = is_elasticgraph_project()

        assert result["is_elasticgraph"] is False
        assert "No Gemfile found" in result["message"]


class TestGraphQLSchema:
    """Tests for GraphQL schema resource."""

    def test_get_schema_success(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test successfully retrieving GraphQL schema."""
        os.chdir(mock_elasticgraph_project)
        result = get_graphql_schema()

        assert result["status"] == "success"
        assert "schema" in result
        assert "type Query" in result["schema"]
        assert result["schema_path"] == COMMON_SCHEMA_PATHS[0]
        assert result["mime_type"] == "application/graphql"

    def test_get_schema_not_in_project(self, temp_dir: Path) -> None:
        """Test getting schema when not in an ElasticGraph project."""
        os.chdir(temp_dir)
        result = get_graphql_schema()

        assert result["status"] == "error"
        assert "No Gemfile found" in result["message"]

    def test_get_schema_file_not_found(self, mock_elasticgraph_project: Path) -> None:
        """Test getting schema when schema file doesn't exist."""
        os.chdir(mock_elasticgraph_project)
        result = get_graphql_schema()

        assert result["status"] == "error"
        assert GRAPHQL_SCHEMA_FILENAME in result["message"]
        assert "not found" in result["message"]

    def test_get_schema_permission_error(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test getting schema when permission denied."""
        os.chdir(mock_elasticgraph_project)
        # Make schema file unreadable
        mock_schema_file.chmod(0o000)

        result = get_graphql_schema()

        assert result["status"] == "error"
        assert "Failed to read" in result["message"]
        assert "Check file permissions" in result["hint"]

        # Restore permissions for cleanup
        mock_schema_file.chmod(0o644)
