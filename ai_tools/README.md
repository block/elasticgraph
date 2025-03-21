# AI Tools

To help you build an ElasticGraph project, you can use these tools with AI agents.

## Components

### ElasticGraph MCP Servier

Located in [`elasticgraph-mcp-server/`](./elasticgraph-mcp-server/), this provides a server implementation for the [Model Context Protocol](https://modelcontextprotocol.io/). MCP enables AI agents to:

- Dynamically discover and use tools through function calling
- Access contextual information through a standardized protocol
- Interact with extensions that provide specific functionality

You can use the MCP server with a variety of tools and platforms, including:

- in [Goose](https://block.github.io/goose/) as an "extension"
- in [Claude](https://docs.anthropic.com/en/docs/agents-and-tools/mcp) Desktop app as an "MCP server"
- in [Cursor](https://docs.cursor.com/context/model-context-protocol) as an "MCP tool"

## Additional Resources

- ElasticGraph follows [llmstxt.org](https://llmstxt.org/) and publishes all documenation concatenated into one `llms-full.txt` file: https://block.github.io/elasticgraph/llms-full.txt
