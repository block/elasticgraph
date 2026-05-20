# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module Jekyll
  # Liquid tag that generates a versioned API doc URL. Links to the latest released version when the
  # referenced page/anchor exists there, falling back to "main" otherwise. This allows user guides to
  # link to new, unreleased APIs (which initially resolve to main) and automatically switch to the
  # latest released version once those APIs ship in a release.
  #
  # Usage:
  #   {% api_doc_url path="ElasticGraph/SchemaDefinition/API.html" anchor="namespace_type-instance_method" %}
  class ApiDocUrl < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @params = {}
      markup.scan(/(\w+)\s*=\s*"([^"]*)"/) do |key, value|
        @params[key] = value
      end
    end

    def render(context)
      site = context.registers[:site]
      path = @params.fetch("path")
      anchor = @params["anchor"]
      latest = site.data.dig("doc_versions", "latest_version")

      version = if latest && doc_exists?(site.source, latest, path, anchor)
        latest
      else
        "main"
      end

      base_url = site.config["baseurl"] || ""
      url = "#{base_url}/api-docs/#{version}/#{path}"
      url += "##{anchor}" if anchor
      url
    end

    private

    def doc_exists?(source, version, path, anchor)
      file_path = File.join(source, "api-docs", version, path)
      return false unless File.exist?(file_path)
      return true unless anchor
      File.read(file_path).include?("id=\"#{anchor}\"")
    end
  end
end

Liquid::Template.register_tag("api_doc_url", Jekyll::ApiDocUrl)
