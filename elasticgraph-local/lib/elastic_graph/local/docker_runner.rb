# Copyright 2024 - 2025 Block, Inc.
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

      def boot
        # :nocov: -- this is actually covered via a call from `boot_as_daemon` but it happens in a forked process so simplecov doesn't see it.
        halt

        prepare_docker_compose_run "up" do |command|
          exec(command) # we use `exec` so that our process is replaced with that one.
        end
        # :nocov:
      end

      def halt
        prepare_docker_compose_run "down --volumes" do |command|
          system(command)
        end
      end

      def boot_as_daemon(halt_command:)
        with_pipe do |read_io, write_io|
          fork do
            # :nocov: -- simplecov can't track coverage that happens in another process
            read_io.close
            Process.daemon
            pid = Process.pid
            $stdout.reopen(write_io)
            $stderr.reopen(write_io)
            puts pid
            boot
            write_io.close
            # :nocov:
          end

          # The `Process.daemon` call in the subprocess changes the pid so we have to capture it this way instead of using
          # the return value of `fork`.
          pid = read_io.gets.to_i

          @output.puts "Booting #{@variant}; monitoring logs for readiness..."

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

          @output.puts
          @output.puts
          @output.puts <<~EOS
            Success! #{@variant} #{@version} (pid: #{pid}) has been booted for the #{@env} environment on port #{@port}.
            It will continue to run in the background as a daemon. To halt it, run:

            #{halt_command}
          EOS
        end
      end

      private

      def prepare_docker_compose_run(*commands)
        name = "#{@env}-#{@version.tr(".", "_")}"

        full_command = commands.map do |command|
          "VERSION=#{@version} PORT=#{@port} UI_PORT=#{@ui_port} ENV=#{@env} docker-compose --project-name #{name} #{command}"
        end.join(" && ")

        ::Dir.chdir(::File.join(__dir__.to_s, @variant.to_s)) do
          yield full_command
        end
      end

      def with_pipe
        read_io, write_io = ::IO.pipe

        begin
          yield read_io, write_io
        ensure
          read_io.close
          write_io.close
        end
      end
    end
  end
end
