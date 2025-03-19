"""
ElasticGraph error creation functions.
"""

from dataclasses import dataclass
from typing import Any

from mcp.shared.exceptions import McpError
from mcp.types import INTERNAL_ERROR


@dataclass
class CommandError:
    """Error details for command execution failures."""

    message: str
    code: int = INTERNAL_ERROR
    data: dict[str, Any] = None

    def __post_init__(self) -> None:
        if self.data is None:
            self.data = {}


def create_command_error(
    message: str,
    result: Any | None = None,
    error: Exception | None = None,
    data: dict[str, Any] | None = None,
) -> McpError:
    """
    Create a McpError with command execution details.

    Args:
        message: Human-readable error message
        result: Optional CompletedProcess result with stdout/stderr
        error: Optional exception that caused the error
        data: Optional additional error data

    Returns:
        McpError instance with error details
    """
    error_data = data or {}

    # Initialize command result fields if any result data is provided
    if result:
        # Handle both CompletedProcess and dict-like objects
        stdout = getattr(result, "stdout", None) or result.get("stdout")
        stderr = getattr(result, "stderr", None) or result.get("stderr")
        exit_code = getattr(result, "returncode", None) or result.get("exit_code")

        error_data.update(
            {
                "stdout": stdout,
                "stderr": stderr,
                "exit_code": exit_code,
            }
        )

    if error:
        error_data.update(
            {
                "error": str(error),
                "error_type": type(error).__name__,
            }
        )

    return McpError(
        CommandError(
            message=message,
            code=INTERNAL_ERROR,
            data=error_data,
        )
    )


def create_not_in_project_error(details: str | None = None) -> McpError:
    """
    Create a McpError indicating not in an ElasticGraph project directory.

    Args:
        details: Optional additional error details

    Returns:
        McpError instance with project directory error details
    """
    return McpError(
        CommandError(
            message="No Gemfile found in current directory",
            code=INTERNAL_ERROR,
            data={
                "hint": "cd into the ElasticGraph project directory",
                "details": details or "Not in an ElasticGraph project directory",
            },
        )
    )
