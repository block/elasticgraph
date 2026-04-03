# AI Tools

To help you build an ElasticGraph project, you can use these tools with AI agents.

## Components

### ElasticGraph MCP Servier

Located in [`elasticgraph-mcp-server/`](./elasticgraph-mcp-server/), this provides a server implementation for the [Model Context Protocol](https://modelcontextprotocol.io/). MCP enables AI agents to:

- Dynamically discover and use tools through function calling
- Access contextual information through a standardized protocol
- Interact with extensions that provide specific functionality

You can use the MCP server with a variety of tools and platforms, including:

- in [Cursor](https://www.cursor.com) as an "MCP tool"
- in [Goose](https://block.github.io/goose/) as an "extension"
- in [Claude Code](https://claude.com/product/claude-code) as an "MCP server"
- in [Codex](https://github.com/openai/codex) as an "MCP server"

## Additional Resources

- ElasticGraph follows [llmstxt.org](https://llmstxt.org/) and publishes all documentation concatenated into one `llms-full.txt` file: https://block.github.io/elasticgraph/llms-full.txt
