# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../../../../script/list_eg_gems"

module ElasticGraph
  RSpec.describe "ElasticGraph gems" do
    gemspecs_by_gem_name = ::Hash.new do |hash, gem_name|
      hash[gem_name] = begin
        gemspec_file = ::File.join(CommonSpecHelpers::REPO_ROOT, gem_name, "#{gem_name}.gemspec")
        eval(::File.read(gemspec_file), ::TOPLEVEL_BINDING.dup, gemspec_file) # standard:disable Security/Eval
      end
    end

    shared_examples_for "an ElasticGraph gem" do |gem_name|
      around do |ex|
        ::Dir.chdir(::File.join(CommonSpecHelpers::REPO_ROOT, gem_name), &ex)
      end

      let(:gemspec) { gemspecs_by_gem_name[gem_name] }

      it "has the correct name" do
        expect(gemspec.name).to eq gem_name
      end

      it "has no symlinked files included in the gem since they do not work correctly when the gem is packaged" do
        symlink_files = gemspec.files.select { |f| ::File.exist?(f) && ::File.ftype(f) == "link" }
        expect(symlink_files).to be_empty
      end

      %w[.yardopts Gemfile .rspec].each do |file|
        it "has a symlinked `#{file}` file" do
          expect(::File.exist?(file)).to be true
          expect(::File.ftype(file)).to eq "link"
        end
      end

      it "has a non-symlinked `LICENSE.txt` file" do
        expect(::File.exist?("LICENSE.txt")).to be true
        expect(::File.ftype("LICENSE.txt")).to eq "file"
        expect(::File.read("LICENSE.txt")).to include("MIT License", /Copyright .* Block, Inc/)
      end
    end

    ::ElasticGraphGems.list.each do |gem_name|
      describe gem_name do
        include_examples "an ElasticGraph gem", gem_name
      end
    end

    # We don't expect any variation in these gemspec attributes.
    %i[authors email homepage license required_ruby_version version].each do |gemspec_attribute|
      it "has the same value for `#{gemspec_attribute}` in all ElasticGraph gemspecs" do
        all_gemspec_values = ::ElasticGraphGems.list.to_h do |gem_name|
          [gem_name, gemspecs_by_gem_name[gem_name].public_send(gemspec_attribute)]
        end

        most_common_value = all_gemspec_values.values.tally.max_by { |_, count| count }.first
        nonstandard_gemspec_values = all_gemspec_values.select { |_, value| value != most_common_value }

        expect(nonstandard_gemspec_values).to be_empty
      end
    end
  end
end
