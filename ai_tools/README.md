# AI Tools

These tools are meant to be used AI agents with function calling capabilities to help you build with ElasticGraph.

## Components

### Model Context Protocol (MCP)

Located in [`modelcontextprotocol/`](./modelcontextprotocol/), this provides a server implementation for the [Model Context Protocol](https://modelcontextprotocol.io/). MCP enables AI agents to:

- Dynamically discover and use tools through function calling
- Access contextual information through a standardized protocol
- Interact with extensions that provide specific functionality

You can use the MCP server with a variety of tools and platforms, including:

- in [Goose](https://block.github.io/goose/) as an "extension"
- in [Claude](https://www.anthropic.com/news/model-context-protocol) Desktop app as an "MCP server"
- in [Cursor](https://docs.cursor.com/context/model-context-protocol) as an "MCP tool"

## Getting Started

See the individual component directories for detailed documentation and setup instructions:
- [Model Context Protocol Server](./modelcontextprotocol/README.md)

## Additional Resources

- ElasticGraph follows [llmstxt.org](https://llmstxt.org/) and publishes an `llms-full.txt` file: https://block.github.io/elasticgraph/llms-full.txt
  - Coming soon `llms.txt` root file
