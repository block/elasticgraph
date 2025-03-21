"""Tests for error handling utilities."""

from typing import Any

import pytest
from mcp.shared.exceptions import McpError
from mcp.types import INTERNAL_ERROR

from elasticgraph_mcp.errors import create_command_error


class TestCommandError:
    """Tests for command error creation functionality."""

    def test_basic(self) -> None:
        """Test creating a basic command error with just a message."""
        message = "Test error message"
        error = create_command_error(message)

        assert isinstance(error, McpError)
        assert error.error.message == message
        assert error.error.code == INTERNAL_ERROR
        assert error.error.data == {}

    def test_with_result(self) -> None:
        """Test creating a command error with command result data."""
        message = "Command failed"
        result = {
            "stdout": "Some output",
            "stderr": "Some error",
            "exit_code": 1,
        }

        error = create_command_error(message, result=result)

        assert error.error.message == message
        assert error.error.data["stdout"] == result["stdout"]
        assert error.error.data["stderr"] == result["stderr"]
        assert error.error.data["exit_code"] == result["exit_code"]

    def test_with_exception(self) -> None:
        """Test creating a command error with an exception."""
        message = "Operation failed"
        exception = ValueError("Invalid value")

        error = create_command_error(message, error=exception)

        assert error.error.message == message
        assert error.error.data["error"] == str(exception)
        assert error.error.data["error_type"] == type(exception).__name__

    def test_with_both(self) -> None:
        """Test creating a command error with both result and exception."""
        message = "Everything failed"
        result = {
            "stdout": "Output",
            "stderr": "Error output",
            "exit_code": 2,
        }
        exception = RuntimeError("Runtime error occurred")

        error = create_command_error(message, result=result, error=exception)

        assert error.error.message == message
        # Check result data
        assert error.error.data["stdout"] == result["stdout"]
        assert error.error.data["stderr"] == result["stderr"]
        assert error.error.data["exit_code"] == result["exit_code"]
        # Check exception data
        assert error.error.data["error"] == str(exception)
        assert error.error.data["error_type"] == type(exception).__name__

    def test_with_partial_result(self) -> None:
        """Test creating a command error with partial result data."""
        message = "Partial failure"
        result = {
            "stderr": "Error output",
            # Missing stdout and exit_code
        }

        error = create_command_error(message, result=result)

        assert error.error.message == message
        assert error.error.data["stderr"] == result["stderr"]
        assert error.error.data["stdout"] is None
        assert error.error.data["exit_code"] is None

    def test_with_none_values(self) -> None:
        """Test creating a command error with None values."""
        message = "Test with None"
        result = {
            "stdout": None,
            "stderr": None,
            "exit_code": None,
        }

        error = create_command_error(message, result=result)

        assert error.error.message == message
        assert all(k in error.error.data for k in ["stdout", "stderr", "exit_code"])
        assert all(error.error.data[k] is None for k in ["stdout", "stderr", "exit_code"])

    @pytest.mark.parametrize(
        "result,expected_data_present",
        [
            ({"stdout": "out"}, True),
            ({"stderr": "err"}, True),
            ({"exit_code": 1}, True),
            ({}, False),
        ],
        ids=[
            "with_stdout",
            "with_stderr",
            "with_exit_code",
            "empty_dict",
        ],
    )
    def test_result_keys(self, result: dict[str, Any], expected_data_present: bool) -> None:
        """Test that command errors contain result data only when provided."""
        error = create_command_error("Test", result=result)

        if expected_data_present:
            # When result has data, all command result keys should be present
            assert all(k in error.error.data for k in ["stdout", "stderr", "exit_code"])
            # Provided values should match
            for key, value in result.items():
                assert error.error.data[key] == value
            # Missing values should be None
            for key in set(["stdout", "stderr", "exit_code"]) - set(result.keys()):
                assert error.error.data[key] is None
        else:
            # When result is empty, no command result fields should be added
            assert error.error.data == {}
