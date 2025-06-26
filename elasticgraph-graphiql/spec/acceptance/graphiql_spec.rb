# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphiql"
require "stringio"
require "nokogiri"

module ElasticGraph
  RSpec.describe GraphiQL, :rack_app do
    let(:app_to_test) { GraphiQL.new(build_graphql, output: ::StringIO.new) }

    it "serves a GraphiQL UI at the root with all assets available" do
      get "/"

      expect(last_response).to be_ok_with_title "ElasticGraph GraphiQL"

      # Parse the HTML to extract all asset references
      doc = Nokogiri::HTML(last_response.body)
      asset_paths = extract_asset_paths(doc)

      # Ensure we found some assets (sanity check)
      expect(asset_paths).not_to be_empty, "Expected to find asset references in the HTML"

      # All asset paths should be relative (not absolute URLs to CDNs)
      absolute_urls = asset_paths.select { |path| path.match?(/^https?:\/\//) }
      expect(absolute_urls).to be_empty, "Found absolute URLs that should be relative paths: #{absolute_urls}"

      # Test that each asset referenced in HTML is available and returns 200
      asset_paths.each do |asset_path|
        get asset_path
        expect(last_response.status).to eq(200),
          "Asset #{asset_path} returned #{last_response.status} instead of 200. " \
          "Response body: #{last_response.body[0, 200]}"
      end
    end

    it "fails with a clear error if the GraphiQL assets cannot be extracted" do
      allow(::Open3).to receive(:capture2e).with(a_string_starting_with("tar ")).and_return(
        ["boom", instance_double(::Process::Status, success?: false, exitstatus: 17)]
      )

      expect {
        get "/"
      }.to raise_error a_string_including("boom")
    end

    def be_ok_with_title(title)
      have_attributes(status: 200, body: a_string_including("<title>#{title}</title>"))
    end

    def extract_asset_paths(doc)
      extarct_assets(doc, "script", "src") +
        extarct_assets(doc, "link", "href") +
        extarct_assets(doc, "img", "src") +
        doc.css("script").text.scan(%r{"(/[^"]+)"}).flatten
    end

    def extarct_assets(doc, tag, attribute)
      doc.css("#{tag}[#{attribute}]").map { |element| element[attribute] }
    end
  end
end
