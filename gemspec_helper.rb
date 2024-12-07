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
        "gem_category" => category.to_s # used by script/update_readme
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

      # Here we define common development dependencies used for the CI build of most of our gems.

      # Linting and style checking gems.
      spec.add_development_dependency "rubocop-factory_bot", "~> 2.26"
      spec.add_development_dependency "rubocop-rake", "~> 0.6"
      spec.add_development_dependency "rubocop-rspec", "~> 3.1"
      spec.add_development_dependency "standard", "~> 1.41.0"

      # Steep is our type checker. Only needed if there's a `sig` directory.
      if ::Dir.exist?(::File.join(gem_dir, "sig"))
        # New steep minor versions often introduce stricter type checks that we may initially fail,
        # so we don't want to automatically upgrade when a new steep minor version is released.
        # Therefore, we list 3 digits (in contrast to most gems).
        spec.add_development_dependency "steep", "~> 1.9.0"
      end

      # If the gem has a `spec` directory then it needs our standard set of testing gems.
      if ::Dir.exist?(::File.join(gem_dir, "spec"))
        spec.add_development_dependency "coderay", "~> 1.1"
        spec.add_development_dependency "flatware-rspec", "~> 2.3", ">= 2.3.3"
        spec.add_development_dependency "rspec", "~> 3.13"
        spec.add_development_dependency "super_diff", "~> 0.13"
        spec.add_development_dependency "simplecov", "~> 0.22"
        spec.add_development_dependency "simplecov-console", "~> 0.9"

        # In addition, if any specs have the `:uses_datastore` tag then we need to pull in gems used by that tag.
        if `git grep -l ":uses_datastore" #{gem_dir}/spec | wc -l`.strip.to_i > 0
          spec.add_development_dependency "httpx", "~> 1.3"
          spec.add_development_dependency "method_source", "~> 1.1"
          spec.add_development_dependency "rspec-retry", "~> 0.6"
          spec.add_development_dependency "vcr", "~> 6.3", ">= 6.3.1"
        end

        # In addition, if any specs have the `:uses_datastore` tag then we need to pull in gems used by that tag.
        if `git grep -l ":factories" #{gem_dir}/spec | wc -l`.strip.to_i > 0
          spec.add_development_dependency "factory_bot", "~> 6.4"
          spec.add_development_dependency "faker", "~> 3.5"
        end

        # If any specs use the `spec_support/lambda_function` helper, then pull in the `aws_lambda_ric` gem,
        # as it contains code that AWS bootstraps Ruby lambdas with. Note that we don't depend on anything
        # specific in this gem, but we want to include it so that our CI build can detect any incompatibilities
        # we may have with it.
        if `git grep -l "spec_support\/lambda_function" #{gem_dir}/spec | wc -l`.strip.to_i > 0
          spec.add_development_dependency "aws_lambda_ric", "~> 2.0"
        end
      end

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
