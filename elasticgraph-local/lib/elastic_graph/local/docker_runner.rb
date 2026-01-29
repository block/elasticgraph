# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "timeout"

module ElasticGraph
  module Local
    # @private
    class DockerRunner
      def initialize(variant, port:, ui_port:, version:, env:, ready_log_line:, daemon_timeout:, output:)
        @variant = variant
        @port = port
        @ui_port = ui_port
        @version = version
        @env = env
        @ready_log_line = ready_log_line
        @daemon_timeout = daemon_timeout
        @output = output
      end

      # :nocov: -- difficult to test `exec` behavior (replaces current process)
      def boot
        halt

        prepare_docker_compose_run "up" do |command|
          exec(command) # we use `exec` so that our process is replaced with that one.
        end
      end
      # :nocov:

      def halt
        prepare_docker_compose_run "down --volumes" do |command|
          system(command)
        end
      end

      def boot_as_daemon(halt_command:)
        halt

        @output.puts "Booting #{@variant}; monitoring logs for readiness..."

        pid = spawn_docker_compose_up do |read_io|
          ::Timeout.timeout(
            @daemon_timeout,
            ::Timeout::Error,
            <<~EOS
              Timed out after #{@daemon_timeout} seconds. The expected "ready" log line[1] was not found in the logs.

              [1] #{@ready_log_line.inspect}
            EOS
          ) do
            loop do
              sleep 0.01
              line = read_io.gets
              @output.puts line
              break if @ready_log_line.match?(line.to_s)
            end
          end
        end

        # Detach so the process continues running after this Ruby process exits.
        ::Process.detach(pid)

        @output.puts
        @output.puts
        @output.puts <<~EOS
          Success! #{@variant} #{@version} (pid: #{pid}) has been booted for the #{@env} environment on port #{@port}.
          It will continue to run in the background as a daemon. To halt it, run:

          #{halt_command}
        EOS
      end

      private

      def spawn_docker_compose_up
        read_io, write_io = ::IO.pipe

        pid = prepare_docker_compose_run("up") do |command|
          spawn(
            command,
            chdir: ::Dir.pwd,
            out: write_io,
            err: write_io
          )
        end

        write_io.close # We don't write from the parent process

        begin
          yield read_io
        ensure
          read_io.close
        end

        pid
      end

      def prepare_docker_compose_run(*commands)
        name = "#{@env}-#{@version.tr(".", "_")}"

        full_command = commands.map do |command|
          "VERSION=#{@version} PORT=#{@port} UI_PORT=#{@ui_port} ENV=#{@env} docker-compose --project-name #{name} #{command}"
        end.join(" && ")

        ::Dir.chdir(::File.join(__dir__.to_s, @variant.to_s)) do
          yield full_command
        end
      end
    end
  end
end
