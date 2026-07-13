#!/usr/bin/env ruby

# This script identifies all of the local ElasticGraph gems in this repo.
# It is designed to be usable from Ruby without shelling out (just require
# it and call `ElasticGraphGems.list`) but also callable from a shell script
# (just run this script).
#
# Note that it does assume that all gems are in a direct subdirectory of the
# repository root. Our glob only looks one level deep to avoid pulling in
# gems that could be installed in `bundle` (e.g. if `bundle --standalone` is
# being used).

module ElasticGraphGems
  def self.list
    repo_root = ::File.expand_path("..", __dir__)
    ::Dir.glob("#{repo_root}/*/*.gemspec").map do |gemspec|
      ::File.basename(::File.dirname(gemspec))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # :nocov: -- specs only require this file, not run it as a script.
  puts ElasticGraphGems.list.join("\n")
  # :nocov:
end
