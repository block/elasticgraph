"""Tests for ElasticGraph MCP server functionality."""

import os
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

import pytest
from mcp.shared.exceptions import McpError

from elasticgraph_mcp.server import (
    get_api_docs,
    get_graphql_schema,
    is_elasticgraph_project,
)


@pytest.fixture
def mock_project_checks():
    """Mock the project directory checks."""
    with patch("elasticgraph_mcp.helpers.run_command") as mock_run:
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
        with pytest.raises(McpError) as exc_info:
            get_graphql_schema()
        assert "No Gemfile found" in str(exc_info.value)

    def test_get_schema_file_not_found(self, mock_elasticgraph_project: Path) -> None:
        """Test getting schema when schema file doesn't exist."""
        os.chdir(mock_elasticgraph_project)
        with pytest.raises(McpError) as exc_info:
            get_graphql_schema()
        assert "schema.graphql not found" in str(exc_info.value)

    def test_get_schema_permission_error(self, mock_elasticgraph_project: Path, mock_schema_file: Path) -> None:
        """Test getting schema when permission denied."""
        os.chdir(mock_elasticgraph_project)
        # Make schema file unreadable
        mock_schema_file.chmod(0o000)

        with pytest.raises(McpError) as exc_info:
            get_graphql_schema()
        assert "Failed to read schema.graphql" in str(exc_info.value)

        # Restore permissions for cleanup
        mock_schema_file.chmod(0o644)


class TestApiDocs:
    """Tests for API documentation resource."""

    @pytest.mark.asyncio
    async def test_get_api_docs_success(self) -> None:
        """Test successfully retrieving API docs."""
        mock_docs = "# ElasticGraph API Documentation\n\n## Overview"

        # Create an async mock response
        mock_response = AsyncMock()
        mock_response.text = mock_docs
        mock_response.raise_for_status = Mock()

        # Create an async mock client
        mock_client = AsyncMock()
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client

        # Patch the AsyncClient class
        with patch("httpx.AsyncClient", return_value=mock_client):
            result = await get_api_docs()

            # Verify operations were called
            mock_client.get.assert_awaited_once()
            mock_response.raise_for_status.assert_called_once()

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

        with patch("elasticgraph_mcp.server.fetch_api_docs", side_effect=mock_fetch):
            with pytest.raises(McpError) as exc_info:
                await get_api_docs()

            error_str = str(exc_info.value)
            assert "Failed to fetch API documentation" in error_str
