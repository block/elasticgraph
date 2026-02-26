# Plan 1: Remove `:except_jruby` from `elasticgraph-local` specs

## Current TODO

`## TODO: Remove `:except_jruby` from `elasticgraph-local` specs`

## Context

Two acceptance tests in `elasticgraph-local/spec/acceptance/rake_tasks_spec.rb` (lines 23, 59) are tagged `:except_jruby`. They pass `--daemonize --pid <file>` to rackup, which calls `Process.daemon` (fork-based) internally. JRuby lacks `fork`.

PR #1037 (commit 2d96f249) was rejected because it complicated the production implementation with `--daemonize` branching logic. The requirement is: keep implementation simple, isolate JRuby workaround to tests only, a seam is fine.

## Approach

**Seam approach**: Extract the `sh` call in `boot_graphiql` into a private `run_rackup(command)` method. The implementation stays trivially simple (one-line delegation). Tests override it at the instance level on JRuby via `define_singleton_method` to use `Process.spawn` + `Process.detach` instead.

This keeps ALL JRuby workaround logic in the test file. The production implementation gains only a clean method extraction with no branching.

## Files to Modify

1. `elasticgraph-local/lib/elastic_graph/local/rake_tasks.rb` - extract `run_rackup` method
2. `elasticgraph-local/spec/acceptance/rake_tasks_spec.rb` - remove `:except_jruby`, add JRuby override, increase wait timeout

## Detailed Changes

### Step 1: Extract `run_rackup` method in rake_tasks.rb

In `elasticgraph-local/lib/elastic_graph/local/rake_tasks.rb`, change line 486 from:

```ruby
sh "ELASTICGRAPH_YAML_FILE=#{@local_config_yaml.shellescape} bundle exec rackup #{::File.join(__dir__.to_s, "config.ru").shellescape} --port #{port} #{args.fetch(:rackup_args)}"
```

To:

```ruby
run_rackup "ELASTICGRAPH_YAML_FILE=#{@local_config_yaml.shellescape} bundle exec rackup #{::File.join(__dir__.to_s, "config.ru").shellescape} --port #{port} #{args.fetch(:rackup_args)}"
```

Add a private method (near the existing private methods at the bottom of the class):

```ruby
def run_rackup(command)
  sh command
end
```

### Step 2: Write failing tests first (TDD)

Remove `:except_jruby` from both specs (lines 23 and 59). Confirm they fail on JRuby (or simulate by temporarily forcing the JRuby code path). Then proceed to step 3.

### Step 3: Add JRuby override in test file

In `elasticgraph-local/spec/acceptance/rake_tasks_spec.rb`, modify `run_rake` to override `run_rackup` on the `RakeTasks` instance when on JRuby:

```ruby
def run_rake(*cli_args, daemon_timeout: nil, batch_size: 1)
  outer_output = nil
  config_dir = ::Pathname.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config"))
  daemon_timeout ||= ENV["CI"] ? 120 : 60

  without_bundler do
    super(*cli_args) do |output|
      outer_output = output

      RakeTasks.new(
        local_config_yaml: config_dir / "settings" / "development.yaml",
        path_to_schema: config_dir / "schema.rb"
      ) do |t|
        t.index_document_sizes = true
        t.schema_element_name_form = :snake_case
        t.env_port_mapping = {"example" => 9615}
        t.elasticsearch_versions = ["8.18.0", "9.0.0"]
        t.opensearch_versions = ["2.19.0"]
        t.output = output
        t.daemon_timeout = daemon_timeout

        t.define_fake_data_batch_for(:widgets) do
          Array.new(batch_size) { build(:widget) }
        end

        # :nocov: -- only runs on JRuby
        if RUBY_ENGINE == "jruby"
          # rackup --daemonize uses fork(), unavailable on JRuby.
          # Override run_rackup to use Process.spawn instead.
          t.define_singleton_method(:run_rackup) do |command|
            pid_file = command[/--pid\s+(\S+)/, 1]
            clean_command = command.gsub(/\s*--daemonize/, "").gsub(/\s*--pid\s+\S+/, "")
            pid = ::Process.spawn(clean_command, [:out, :err] => [::File::NULL, "w"])
            ::Process.detach(pid)
            ::File.write(pid_file, pid.to_s) if pid_file
          end
        end
        # :nocov:
      end
    end
  end
rescue ::Timeout::Error => e
  raise ::Timeout::Error.new("#{outer_output.string}\n\n#{e.message}")
end
```

### Step 4: Increase JRuby wait timeout

In `wait_for_server_readiness`, increase local iterations from 50 to 150 to accommodate JRuby JVM startup overhead. The loop returns as soon as the server responds, so this doesn't slow MRI tests:

```ruby
iterations = ENV["CI"] ? 300 : 150
```

## Verification

1. Run the two previously-skipped specs locally on MRI to confirm they still pass with `run_rackup` extraction.
2. On JRuby (or by temporarily forcing `RUBY_ENGINE == "jruby"` check), confirm the `Process.spawn` path works.
3. Run `script/lint` to catch style issues.

## Planning Session

`/Users/myron.marston/.claude/projects/-Users-myron-marston-code-elasticgraph/f2f27953-57fc-4169-8f1d-35ce9c3e571e.jsonl`

## Unresolved Questions

(None)
