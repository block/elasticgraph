# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph-support/lib/elastic_graph/version"

module ElasticGraphGemspecHelper
  # Helper methor for defining a gemspec for an elasticgraph gem.
  def self.define_elasticgraph_gem(gemspec_file:, category:)
    gem_dir = ::File.expand_path(::File.dirname(gemspec_file))
    validate_gem(gem_dir)

    ::Gem::Specification.new do |spec|
      spec.name = ::File.basename(gemspec_file, ".gemspec")
      spec.version = ElasticGraph::VERSION
      spec.authors = ["Myron Marston", "Ben VandenBos", "Block Engineering"]
      spec.email = ["myron@squareup.com"]
      spec.homepage = "https://block.github.io/elasticgraph/"
      spec.license = "MIT"
      spec.metadata["gem_category"] = category.to_s

      # See https://guides.rubygems.org/specification-reference/#metadata
      # for metadata entries understood by rubygems.org.
      spec.metadata = {
        "bug_tracker_uri" => "https://github.com/block/elasticgraph/issues",
        "changelog_uri" => "https://github.com/block/elasticgraph/releases/tag/v#{ElasticGraph::VERSION}",
        "documentation_uri" => "https://block.github.io/elasticgraph/docs/main/", # TODO(#2): update this URL to link to the exact doc version
        "homepage_uri" => "https://block.github.io/elasticgraph/",
        "source_code_uri" => "https://github.com/block/elasticgraph/tree/v#{ElasticGraph::VERSION}/#{spec.name}",
        "gem_category" => category.to_s # used by script/update_codebase_overview
      }

      # Specify which files should be added to the gem when it is released.
      # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
      # We also remove `.rspec` and `Gemfile` because these files are not needed in
      # the packaged gem (they are for local development of the gems) and cause a problem
      # for some users of the gem due to the fact that they are symlinks to a parent path.
      spec.files = ::Dir.chdir(gem_dir) do
        `git ls-files -z`.split("\x0").reject do |f|
          (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features|sig)/|\.(?:git|travis|circleci)|appveyor)})
        end - [".rspec", "Gemfile", ".yardopts"]
      end

      spec.bindir = "exe"
      spec.executables = spec.files.grep(%r{\Aexe/}) { |f| ::File.basename(f) }
      spec.require_paths = ["lib"]
      spec.required_ruby_version = "~> 3.2"

      yield spec, ElasticGraph::VERSION

      if (symlink_files = spec.files.select { |f| ::File.exist?(f) && ::File.ftype(f) == "link" }).any?
        raise "#{symlink_files.size} file(s) of the `#{spec.name}` gem are symlinks, but " \
          "symlinks do not work correctly when the gem is packaged. Symlink files: #{symlink_files.inspect}"
      end
    end
  end

  def self.validate_gem(gem_dir)
    gem_warnings = validate_symlinked_file(::File.join(gem_dir, ".yardopts"))

    gem_issues = []
    gem_issues.concat(validate_symlinked_file(::File.join(gem_dir, "Gemfile")))
    gem_issues.concat(validate_symlinked_file(::File.join(gem_dir, ".rspec")))
    gem_issues.concat(validate_license(gem_dir))

    unless gem_warnings.empty?
      warn "WARNING: Gem #{::File.basename(gem_dir)} has the following issues:\n\n" + gem_warnings.join("\n")
    end

    return if gem_issues.empty?

    abort "Gem #{::File.basename(gem_dir)} has the following issues:\n\n" + gem_issues.join("\n")
  end

  def self.validate_symlinked_file(file)
    gem_issues = []

    if ::File.exist?(file)
      if ::File.ftype(file) != "link"
        gem_issues << "`#{file}` must be a symlink."
      end
    else
      gem_issues << "`#{file}` is missing."
    end

    gem_issues
  end

  def self.validate_license(gem_dir)
    gem_issues = []

    file = ::File.join(gem_dir, "LICENSE.txt")
    if ::File.exist?(file)
      if ::File.ftype(file) == "link"
        gem_issues << "`#{file}` must not be a symlink."
      end

      contents = ::File.read(file)
      unless contents.include?("MIT License")
        gem_issues << "`#{file}` must contain 'MIT License'."
      end

      unless contents.include?("Copyright (c) 2024 Block, Inc.")
        gem_issues << "`#{file}` must contain Block copyright notice."
      end
    else
      gem_issues << "`#{file}` is missing."
    end

    gem_issues
  end
end
