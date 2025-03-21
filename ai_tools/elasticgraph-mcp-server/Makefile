# Development tasks for ElasticGraph MCP

.PHONY: help install dev test format lint server inspector

# Default target when just running 'make'
.DEFAULT_GOAL := help

# Colors for terminal output
BLUE := \033[34m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help: ## Show this help message
	@echo "$(BLUE)ElasticGraph MCP Server Development Commands$(RESET)"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'

install: ## Install dependencies using uv
	@echo "$(BLUE)Installing dependencies...$(RESET)"
	uv sync

dev: format lint test ## Run format, lint, and test (main development command)
	@echo "$(GREEN)All development checks completed!$(RESET)"

test: ## Run tests
	@echo "$(BLUE)Running tests...$(RESET)"
	pytest -v
	@echo "$(GREEN)Tests completed!$(RESET)"

format: ## Format code with ruff
	@echo "$(BLUE)Formatting code with ruff...$(RESET)"
	ruff format .
	@echo "$(GREEN)Formatting completed!$(RESET)"

lint: ## Run ruff linting with auto-correct
	@echo "$(BLUE)Running ruff linting with auto-correct...$(RESET)"
	ruff check --fix .
	@echo "$(GREEN)Linting completed!$(RESET)"

# Development server commands
server: ## Run the MCP server
	@echo "$(BLUE)Starting MCP server...$(RESET)"
	uv pip install .
	elasticgraph-mcp-server

inspector: ## Run the MCP Inspector with browser UI
	@echo "$(BLUE)Starting MCP Inspector...$(RESET)"
	mcp dev src/elasticgraph_mcp/server.py
