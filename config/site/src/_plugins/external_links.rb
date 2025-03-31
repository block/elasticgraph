# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "nokogiri"

module Jekyll
  # Hook into the post_render event to modify links in the final HTML
  Jekyll::Hooks.register :pages, :post_render do |page|
    next unless page.output_ext == ".html"

    doc = Nokogiri::HTML(page.output)
    site_url = page.site.config.fetch("baseurl")

    # Find all links
    doc.css("a").each do |link|
      href = link["href"]
      next unless href

      links_to_external_page = href.start_with?("http://", "https://") && !href.start_with?(site_url)
      links_to_api_docs_without_nav = href.match?(%r{/api-docs/.+})
      links_to_non_html_page = (href[/\.([^.]+)\z/, 1] || "html") != "html"

      # Add `target=_blank rel=nokogiri` to any link that goes to a page that lacks our site nav, including:
      # - All external links.
      # - Pages under `/api-docs/` (except for `/api-docs/` itself) as the YARD-generated pages don't have the site nav.
      # - Non-html resources.
      if links_to_external_page || links_to_api_docs_without_nav || links_to_non_html_page
        link["target"] = "_blank"
        link["rel"] = "noopener"
      end
    end

    page.output = doc.to_html
  end
end
