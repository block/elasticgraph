# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "thor"
require "fileutils"
require "shellwords"

module ElasticGraph
  class CLI < Thor
    include Thor::Actions

    # Tell Thor where our template files live
    def self.source_root
      # This expands to elasticgraph/project_template
      File.expand_path("../../project_template", __dir__)
    end

    desc "new APP_NAME", "Generate a new ElasticGraph project named APP_NAME."
    def new(app_name)
      new_app_path = resolve_new_app_path(app_name)

      say "Creating a new ElasticGraph app called '#{app_name}' at: #{new_app_path}", :green

      # Ensure the directory is created (Thor's directory command will also create it if missing)
      empty_directory(new_app_path) unless Dir.exist?(new_app_path)

      # Recursively copy all files from project_template/ into the new_app_path
      directory ".", new_app_path

      # Replace references to `template_example` and `TemplateExample`
      # Bootstrap.find_and_replace_in_files "template_example", app_name
      # module_name = app_name.split("_").map(&:capitalize).join
      # Bootstrap.find_and_replace_in_files "TemplateExample", module_name

      say "Successfully created '#{app_name}' folder.", :green

      say <<~INSTRUCTIONS, :yellow
        Next steps:
          1. cd #{new_app_path}
          2. Customize your new project as needed
          3. Run `rake -T` to view available tasks
          4. Boot locally with `rake boot_locally`
      INSTRUCTIONS
    end

    private

    # Determine if we should create the new project parallel to the 'elasticgraph'
    # directory, or simply within the current directory.
    def resolve_new_app_path(app_name)
      current_dir = Dir.pwd
      base_name   = File.basename(current_dir)

      if base_name == "elasticgraph"
        parent_dir = File.dirname(current_dir)
        File.join(parent_dir, app_name)
      else
        File.join(current_dir, app_name)
      end
    end
  end
end

module MakeBackticksSafe
  def `(command)r
    output = super("#{command} 2>&1")
    status = $?
    return output.chomp if status&.success?
    raise "`#{command}` failed: #{output}"
  end
end

# Override the backticks method to make it raise an error if the command fails.
::Kernel.prepend(MakeBackticksSafe)

module Bootstrap
  extend FileUtils # from Rake, provides `sh` method.

  def self.find_and_replace_in_files(old_text, new_text)
    files = `git grep --files-with-matches --no-color --text #{old_text.shellescape}`.chomp.split("\n")
    files.each do |file|
      contents = File.read(file).gsub(old_text, new_text)
      File.write(file, contents)
    end
  end

  def self.quiet_sh(*cmd, &)
    sh(*cmd, verbose: false, out: File::NULL, &)
  end
end
