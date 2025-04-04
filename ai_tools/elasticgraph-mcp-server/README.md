# ElasticGraph MCP Server

This provides a Model Context Protocol (MCP) server for [ElasticGraph](https://block.github.io/elasticgraph/) using the [MCP python-sdk](https://github.com/modelcontextprotocol/python-sdk).

## Setup

1. Install dependencies:

```bash
# make install
uv sync

source .venv/bin/activate
```

2. Run the server:

The server runs on port 3000, and though there are no logs displayed, it is actively waiting for input.

```bash
# make server
uv pip install .
elasticgraph-mcp-server
```

## Development

### MCP Inspector

You can test your MCP server with Anthropic's [Inspector](https://modelcontextprotocol.io/docs/tools/inspector). To start:

1. Run the following command, which starts the server as a subprocess and launches the Inspector UI:

```bash
# make inspector
mcp dev src/elasticgraph_mcp/server.py
```

2. Open your browser and navigate to [http://localhost:5173](http://localhost:5173) to access the MCP Inspector UI.

### Goose

Add a development build to Goose:

1. In Goose, navigate to **Settings > Extensions > Add**.
2. Set **Type** to **StandardIO**.
3. Paste the run command for your local development version, it will start with `uv run </path/to/elasticgraph_mcp/.venv/bin/elasticgraph-mcp-server>`

```bash
# Copy the run command to your clipboard
echo "uv run $(realpath .venv/bin/elasticgraph-mcp-server)" | pbcopy
```


4. Enable the extension and verify that Goose recognizes your tools.

Ask goose: What tools and resources for ElasticGraph do you have?

## Development commands

This project uses `make` for common development tasks. To see all available commands, run:

```bash
make help
```

## Using Goose to help with development

You can use [Goose](https://block.github.io/goose/) to improve this MCP server. To teach goose about MCP, follow these steps:

### Setting Up a Goose Session

1. **Navigate to this MCP Server Directory:**

```bash
cd ai_tools/elasticgraph-mcp-server
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

Try this prompt:
> First, learn about MCP servers from `tmp/mcp_for_llm_instructions.md`. Then, see the current MCP server I'm building in `src/elasticgraph_mcp/server.py`. Now <specify your changes>

## Releases

The [elasticgraph-mcp-server](https://pypi.org/project/elasticgraph-mcp-server/) package is published to PyPI via a GitHub workflow manual action. See `.github/workflows/publish-mcp-server.yaml`.

To publish a new version bump the `.ai_tools/elasticgraph-mcp-server/pyproject.toml` version and then manually trigger the workflow via the GitHub Action UI: https://github.com/block/elasticgraph/actions.
