# Model Context Protocol (MCP) Server for ElasticGraph

This provides an MCP server for ElasticGraph using the [python-sdk](https://github.com/modelcontextprotocol/python-sdk).

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Running the Server](#running-the-server)
  - [Deployed Artifact](#running-from-the-deployed-artifact)
  - [Make Command](#running-via-make)
- [Development Commands](#development-commands)
- [Testing with MCP Inspector](#testing-with-mcp-inspector)
- [Using Goose for Development](#using-goose-for-development)
  - [Setting Up a Goose Session](#setting-up-a-goose-session)
  - [Adding a Development Build to Goose](#adding-a-development-build-to-goose)
- [TODO](#todo)
- [Development Tools](#development-tools)

## Overview

## Installation

**Initialize & Activate the Python Environment:**
   ```bash
   make install  # Install dependencies using uv
   source .venv/bin/activate
   ```

## Running the Server

### Running from the Deployed Artifact

Run the MCP server directly using:

```bash
uvx mcp_elasticgraph
```

> **Note:** If you run this command without any flags, the process may appear stuck. This is normal—the MCP STDIO protocol expects message exchange over STDIO, indicating that the server is ready.

Alternatively, you can use:

```bash
goose session --with-extension "uvx mcp_elasticgraph"
```

### Running via Make Command

Start the server using:

```bash
make server
```

The server runs on port 3000, and though there are no logs displayed, it is actively waiting for input.

## Development Commands

This project uses `make` for common development tasks. To see all available commands, run:

```bash
make help
```

Some useful commands include:

- **Install Dependencies:** `make install`
- **Run Format, Lint, and Tests:** `make dev`
- **Start the MCP Server:** `make server`
- **Launch the MCP Inspector:** `make inspector`

## Testing with MCP Inspector

You can test your MCP server with Anthropic's [Inspector](https://modelcontextprotocol.io/docs/tools/inspector). To start:

1. Run the following command, which starts the server as a subprocess and launches the Inspector UI:
   ```bash
   make inspector
   ```
2. Open your browser and navigate to [http://localhost:5173](http://localhost:5173) to access the MCP Inspector UI.

## Using Goose for Development

### Setting Up a Goose Session

1. **Navigate to the Project Directory:**

   ```bash
   cd mcp_elasticgraph
   ```

2. **Prepare a Temporary Directory:**

   ```bash
   mkdir tmp
   touch tmp/.gitignore
   echo "/*" > tmp/.gitignore
   ```

3. **Create MCP Instructions File:**
   Copy MCP instructions from [MCP LLM instructions](https://modelcontextprotocol.io/llms-full.txt) to a new file:

   ```bash
   touch tmp/mcp_for_llm_instructions.md
   ```

4. **Start a Goose Session:**
   ```bash
   goose session
   ```
   Then follow the prompt:
   > _First, learn about MCP server from `tmp/mcp_for_llm_instructions.md`. Then, see the current MCP server I'm building in `src/mcp_elasticgraph/server.py`. Now..._

### Adding a Development Build to Goose

1. In Goose, navigate to **Settings > Extensions > Add**.
2. Set **Type** to **StandardIO**.
3. Obtain the absolute path to the project’s CLI:
   ```bash
   # Get the path and copy it to your clipboard
   realpath .venv/bin/mcp_elasticgraph | pbcopy
   ```
4. Paste the path after typing `uv run`:
   ```bash
   uv run </path/to/mcp_elasticgraph/.venv/bin/mcp_elasticgraph>
   ```
5. Enable the extension and verify that Goose recognizes your tools.

## TODO

- [x] Install `elasticgraph` gem
- [x] Create a new ElasticGraph project
- [x] Add `rake -T` tasks to help create a new "resource"
- [x] Simplify by creating new resources with CLI and rake commands (e.g., `schema:dump`)
- [ ] Load LLM data from `llms-full.txt` file
- [ ] Query local instance in plain language

## Development Tools

This project employs several tools for development:

- **make:** Common task runner (see `make help` for available commands)
- **ruff:** Code formatting and linting tool
- **pytest:** Testing framework

This reorganization should improve clarity and ease navigation through installation, running, development, and testing instructions.

**URLs:**

- Python SDK: https://github.com/modelcontextprotocol/python-sdk
- MCP Inspector: https://modelcontextprotocol.io/docs/tools/inspector
- MCP LLM Instructions: https://modelcontextprotocol.io/llms-full.txt
