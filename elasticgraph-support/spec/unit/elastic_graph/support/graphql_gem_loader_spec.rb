# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/graphql_gem_loader"

module ElasticGraph
  module Support
    RSpec.describe GraphQLGemLoader do
      before do
        GraphQLGemLoader.send(:reset_warning_state!)
      end

      describe ".load" do
        it "prints a yellow warning to stderr when graphql-c_parser is unavailable" do
          simulate_missing_gems "graphql/c_parser"

          expect {
            GraphQLGemLoader.load
          }.to output(/\[ElasticGraph\] For better performance, add `graphql-c_parser` to your Gemfile/).to_stderr
        end

        it "prints the warning only once across multiple calls" do
          simulate_missing_gems "graphql/c_parser"

          stderr_output = StringIO.new
          original_stderr = $stderr
          $stderr = stderr_output

          begin
            GraphQLGemLoader.load
            GraphQLGemLoader.load
            GraphQLGemLoader.load
          ensure
            $stderr = original_stderr
          end

          expect(stderr_output.string.scan("graphql-c_parser").size).to eq(1)
        end

        it "still raises if the graphql gem is unavailable" do
          simulate_missing_gems "graphql", "graphql/c_parser"

          expect {
            GraphQLGemLoader.load
          }.to raise_error(LoadError)
        end

        it "does not print a warning when graphql-c_parser loads successfully" do
          # The gem is installed in development, so require will succeed without stubbing
          expect {
            GraphQLGemLoader.load
          }.not_to output.to_stderr
        end

        def simulate_missing_gems(*gems)
          allow(GraphQLGemLoader).to receive(:require).and_call_original

          gems.each do |gem_name|
            allow(GraphQLGemLoader).to receive(:require).with(gem_name).and_raise(LoadError)
          end
        end
      end
    end
  end
end
