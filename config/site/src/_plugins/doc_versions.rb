# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module Jekyll
  class DocVersions < Generator
    def generate(site)
      # Get all subdirectories in src/docs
      docs_dir = File.join(site.source, "docs")
      versions = if Dir.exist?(docs_dir)
        Dir.entries(docs_dir)
          .select { |f| File.directory?(File.join(docs_dir, f)) && f !~ /^\./ }
          .sort_by { |v| (v == "main") ? "0" : Gem::Version.new(v.delete_prefix("v")) }
          .reverse
      else
        []
      end

      # Add the data to site.data
      site.data["doc_versions"] = {"versions" => versions, "latest_version" => versions.first}
    end
  end
end
