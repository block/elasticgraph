"""Tests for ElasticGraph MCP server functionality."""

import os
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest

from mcp_elasticgraph.helpers import GRAPHQL_SCHEMA_FILENAME
from mcp_elasticgraph.server import (
    get_api_docs,
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

        assert "content" in result
        assert len(result["content"]) == 1
        assert result["content"][0]["type"] == "text"
        assert "This is an ElasticGraph project" in result["content"][0]["text"]

    def test_invalid_project(self, temp_dir: Path) -> None:
        """Test detecting an invalid project directory."""
        result = is_elasticgraph_project()

        assert "content" in result
        assert len(result["content"]) == 1
        assert result["content"][0]["type"] == "text"
        assert "This is not an ElasticGraph project" in result["content"][0]["text"]
        assert "No Gemfile found" in result["content"][0]["text"]


class TestGraphQLSchema:
    """Tests for GraphQL schema resource."""

    def test_get_schema_success(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test successfully retrieving GraphQL schema."""
        os.chdir(mock_elasticgraph_project)
        result = get_graphql_schema()

        assert "contents" in result
        assert len(result["contents"]) == 1
        assert result["contents"][0]["uri"] == "schema://graphql"
        assert result["contents"][0]["mimeType"] == "application/graphql"
        assert "type Query" in result["contents"][0]["text"]

    def test_get_schema_not_in_project(self, temp_dir: Path) -> None:
        """Test getting schema when not in an ElasticGraph project."""
        os.chdir(temp_dir)
        result = get_graphql_schema()

        assert "contents" in result
        assert len(result["contents"]) == 1
        assert result["contents"][0]["uri"] == "schema://graphql"
        assert result["contents"][0]["mimeType"] == "text/plain"
        assert "No Gemfile found" in result["contents"][0]["text"]

    def test_get_schema_file_not_found(self, mock_elasticgraph_project: Path) -> None:
        """Test getting schema when schema file doesn't exist."""
        os.chdir(mock_elasticgraph_project)
        result = get_graphql_schema()

        assert "contents" in result
        assert len(result["contents"]) == 1
        assert result["contents"][0]["uri"] == "schema://graphql"
        assert result["contents"][0]["mimeType"] == "text/plain"
        assert GRAPHQL_SCHEMA_FILENAME in result["contents"][0]["text"]
        assert "not found" in result["contents"][0]["text"]

    def test_get_schema_permission_error(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test getting schema when permission denied."""
        os.chdir(mock_elasticgraph_project)
        # Make schema file unreadable
        mock_schema_file.chmod(0o000)

        result = get_graphql_schema()

        assert "contents" in result
        assert len(result["contents"]) == 1
        assert result["contents"][0]["uri"] == "schema://graphql"
        assert result["contents"][0]["mimeType"] == "text/plain"
        assert "Failed to read" in result["contents"][0]["text"]
        assert "Check file permissions" in result["contents"][0]["text"]

        # Restore permissions for cleanup
        mock_schema_file.chmod(0o644)


class TestApiDocs:
    """Tests for API documentation resource."""

    @pytest.mark.asyncio
    async def test_get_api_docs_success(self) -> None:
        """Test successfully retrieving API docs."""
        mock_docs = "# ElasticGraph API Documentation\n\n## Overview"
        with patch("httpx.AsyncClient.get") as mock_get:
            # Create mock response
            mock_response = AsyncMock()
            mock_response.text = mock_docs
            mock_get.return_value = mock_response

            result = await get_api_docs()

            # Verify the response was properly awaited
            mock_response.raise_for_status.assert_awaited_once()

            assert "contents" in result
            assert len(result["contents"]) == 1
            assert result["contents"][0]["uri"] == "docs://api"
            assert result["contents"][0]["mimeType"] == "text/plain"
            assert result["contents"][0]["text"] == mock_docs

    @pytest.mark.asyncio
    async def test_get_api_docs_failure(self) -> None:
        """Test handling API docs fetch failure."""
        async def mock_fetch():
            return None
            
        with patch("mcp_elasticgraph.server.fetch_api_docs", side_effect=mock_fetch):
            result = await get_api_docs()

            assert "contents" in result
            assert len(result["contents"]) == 1
            assert result["contents"][0]["uri"] == "docs://api"
            assert result["contents"][0]["mimeType"] == "text/plain"
            assert "Error: Failed to fetch API documentation" in result["contents"][0]["text"]
            assert "check your internet connection" in result["contents"][0]["text"].lower()
