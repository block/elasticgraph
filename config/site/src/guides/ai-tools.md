---
layout: markdown
title: AI Tools
permalink: /guides/ai-tools/
---

Build faster with ElasticGraph using AI tools. Here's how to get started with ChatGPT, Claude, or your preferred LLM.

## Quick Start

### Get the docs

[llms-full.txt]({% link llms-full.txt %}) contains our documentation optimized for LLMs.

### Copy the prompt

{% highlight text %}
I'm building with ElasticGraph. Here's the documentation:

[the contents of llms-full.txt go here]
{% endhighlight %}

<button id="copy-button" class="btn-primary">Copy this prompt</button>

### Start building

Ask your favorite LLM about:

- Defining your schema
- Configuring Elasticsearch/OpenSearch
- Writing ElasticGraph GraphQL queries
- Searching and aggregating your data

## ElasticGraph MCP Server

The [elasticgraph-mcp-server](https://pypi.org/project/elasticgraph-mcp-server/) enables AI agents to interact with your ElasticGraph projects through the [Model Context Protocol](https://modelcontextprotocol.io/). This allows AI tools to:

- Access ElasticGraph documentation
- Write schema definitions or GraphQL queries grounded in the full ElasticGraph docs
- Run common ElasticGraph commands

### Installation

Install and run the MCP server, for example as a [Goose extension](https://block.github.io/goose/docs/getting-started/using-extensions), using:

{% highlight bash %}
uvx elasticgraph-mcp-server
{% endhighlight %}

Full documentation for [elasticgraph-mcp-server](https://pypi.org/project/elasticgraph-mcp-server/).

### Compatible AI Tools

You can use the ElasticGraph MCP server with:

- [Goose](https://block.github.io/goose/) - as an extension
- Claude - in the desktop app as an MCP server
- [Cursor](https://docs.cursor.com/context/model-context-protocol) - as an MCP tool

<script>
document.addEventListener('DOMContentLoaded', function() {
  const copyButton = document.getElementById('copy-button');
  const prefix = "I'm building with ElasticGraph. Here's the documentation:\n\n";
  const docs = {{ site.data.content.llm_content.content | jsonify }};
  const fullTemplate = prefix + docs;

  copyButton.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(fullTemplate);
      const originalText = copyButton.textContent;
      copyButton.textContent = 'Copied!';
      copyButton.classList.remove('btn-primary');
      copyButton.classList.add('btn-success');
      setTimeout(() => {
        copyButton.textContent = originalText;
        copyButton.classList.remove('btn-success');
        copyButton.classList.add('btn-primary');
      }, 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
      copyButton.textContent = 'Failed to copy';
    }
  });
});
</script>
