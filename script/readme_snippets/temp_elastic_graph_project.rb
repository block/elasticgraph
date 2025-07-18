# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "fileutils"
require "tempfile"
require "shellwords"

# Manages a persistent ElasticGraph project for validation
# This project is created once in <repo_root>/tmp/ and reused across runs
class TempElasticGraphProject
  attr_reader :path

  def initialize(repo_root)
    project_name = "example_project_for_snippet_validation"
    @path = File.join(repo_root, "tmp", project_name)

    if File.exist?(path)
      puts "🔄 Using existing ElasticGraph project at #{path}"
      reset_git
    else
      puts "🏗️  Creating new ElasticGraph project for validation..."

      # Ensure tmp directory exists
      FileUtils.mkdir_p(File.dirname(path))

      # Run elasticgraph new command from the repository root with ELASTICGRAPH_GEMS_PATH
      Dir.chdir(repo_root) do
        env = {"ELASTICGRAPH_GEMS_PATH" => repo_root}
        output = `#{env.map { |k, v| "#{k}=#{Shellwords.escape(v)}" }.join(" ")} bundle exec elasticgraph new #{Shellwords.escape(path)} 2>&1`
        unless $?.success?
          puts "❌ Failed to create ElasticGraph project:"
          puts output
          exit(1)
        end
      end

      puts "✅ ElasticGraph project created at #{path}"
    end

    yield self
  end

  def in_dir(&block)
    Dir.chdir(path, &block)
  end

  def sandbox
    original_docker_ids = running_container_ids
    yield
  ensure
    reset_git
    new_containers = running_container_ids - original_docker_ids

    unless new_containers.empty?
      output = `docker stop #{new_containers.join(" ")}`
      unless $?.success?
        puts "⚠️  Warning: Failed to stop docker containers (#{new_containers.join(", ")}): #{output}"
      end
    end
  end

  private

  def reset_git
    in_dir do
      # Reset to the initial commit (elasticgraph new creates a git repo with initial commit)
      output = `git reset --hard HEAD 2>&1 && git clean -fd 2>&1`
      unless $?.success?
        puts "⚠️  Warning: Failed to reset temp project: #{output}"
      end
    end
  end

  def running_container_ids
    output = `docker ps -q`

    unless $?.success?
      puts "⚠️  Warning: Failed to identify running docker containers: #{output}"
    end

    output.split("\n")
  end
end
