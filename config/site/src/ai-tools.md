---
layout: markdown
title: AI Tools
permalink: /ai-tools/
---

Build faster with ElasticGraph using AI tools. Here's how to get started with ChatGPT, Claude, or your preferred LLM.

## Quick Start

### Get the docs

Visit [llms-full.txt]({% link llms-full.txt %}) to copy our API docs optimized for LLMs.

### Copy the prompt

{% highlight text %}
I'm building with ElasticGraph. Here's the documentation:

[Paste llms-full.txt content here]
{% endhighlight %}

<button id="copy-button" class="btn-primary">Copy AI Prompt</button>

_Use this button to copy the prompt above **including** the full [llms-full.txt]({% link llms-full.txt %}) documentation._

### Start building

Ask your favorite LLM about:

- Writing GraphQL queries
- Setting up filters and aggregations
- Defining your schema
- Configuring Elasticsearch/OpenSearch

<script>
   document.addEventListener('DOMContentLoaded', async function() {
   const copyButton = document.getElementById('copy-button');

   try {
      // Fetch the documentation content
      const response = await fetch('{% link llms-full.txt %}');
      const docs = await response.text();

      // Create the full template with the docs
      const fullTemplate = `I'm building with ElasticGraph. Here's the documentation:

   ${docs}`;


      // Set up copy functionality
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
         copyButton.classList.add('bg-red-500');
         }
      });
   } catch (err) {
      console.error('Failed to load documentation:', err);
   }
   });
</script>
