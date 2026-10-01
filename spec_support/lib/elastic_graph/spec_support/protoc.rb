# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "rbconfig"

module ElasticGraph
  module SpecSupport
    module Protoc
      # The `grpc-tools` gem vendors precompiled `protoc` binaries under `bin/<arch>-<os>/`.
      # Locate the binary directly because its Ruby wrapper conflicts with JRuby's `PLATFORM` constant.
      # simplecov:disable -- only one platform's branches can execute in any given run.
      PROTOC_BINARY = begin
        arch =
          if RbConfig::CONFIG["host_os"].match?(/darwin/)
            "x86_64" # Apple Silicon uses the x86_64 binary under Rosetta; the gem ships no arm64 build.
          elsif RbConfig::CONFIG["host_cpu"].match?(/x86_64|amd64/)
            "x86_64"
          else
            "x86"
          end

        os =
          case RbConfig::CONFIG["host_os"]
          when /darwin/ then "macos"
          when /mswin|mingw|cygwin/ then "windows"
          else "linux"
          end

        bin_dir = ::File.expand_path("bin/#{arch}-#{os}", Gem.loaded_specs.fetch("grpc-tools").full_gem_path)
        ::File.join(bin_dir, "protoc#{RbConfig::CONFIG["EXEEXT"]}").tap do |binary|
          raise "`grpc-tools` ships no `protoc` for #{arch}-#{os}; expected it at #{binary}." unless ::File.exist?(binary)
        end
      end
      # simplecov:enable
    end
  end
end
