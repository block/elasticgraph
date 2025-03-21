"""Common test configuration and fixtures."""

import os
import tempfile
from collections.abc import Generator
from pathlib import Path

import pytest

from elasticgraph_mcp.helpers import GRAPHQL_SCHEMA_FILENAME


@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for testing.

    Yields:
        Path to temporary directory. Directory and contents are cleaned up after test.
    """
    with tempfile.TemporaryDirectory() as tmpdirname:
        original_dir = os.getcwd()
        os.chdir(tmpdirname)
        yield Path(tmpdirname)
        os.chdir(original_dir)


@pytest.fixture
def mock_elasticgraph_project(temp_dir: Path) -> Path:
    """Create a mock ElasticGraph project structure.

    Args:
        temp_dir: Temporary directory fixture

    Returns:
        Path to mock project directory
    """
    # Create minimal project structure
    project_dir = temp_dir / "test_project"
    project_dir.mkdir()

    # Create Gemfile with elasticgraph dependency
    gemfile = project_dir / "Gemfile"
    gemfile.write_text('source "https://rubygems.org"\ngem "elasticgraph"')

    return project_dir


@pytest.fixture
def mock_schema_file(mock_elasticgraph_project: Path) -> Path:
    """Create a mock GraphQL schema file.

    Args:
        mock_elasticgraph_project: Mock project directory fixture

    Returns:
        Path to mock schema file
    """
    # Create schema directory structure
    schema_dir = mock_elasticgraph_project / "config" / "schema" / "artifacts"
    schema_dir.mkdir(parents=True)

    # Create mock schema file
    schema_file = schema_dir / GRAPHQL_SCHEMA_FILENAME
    schema_file.write_text(
        """
type Query {
  hello: String!
}

type Show {
  attendance: Int
  startedAt: DateTime
  venue: Venue
}
"""
    )

    return schema_file
