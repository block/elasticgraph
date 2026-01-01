# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"
require "yaml"

module ElasticGraph
  module Support
    RSpec.describe Config do
      describe ".define" do
        it "defines a data class with the named attributes" do
          config_def = Config.define(:size, :name) do
            json_schema at: "test", optional: false
          end

          valid_config = config_def.new(size: 10, name: "test")

          expect(valid_config.size).to eq(10)
          expect(valid_config.name).to eq("test")
          expect(valid_config).to be_a(::Data)
        end

        it "validates upon instantiation" do
          config_def = Config.define(:size, :name) do
            json_schema at: "test", optional: false,
              properties: {
                size: {type: "integer", minimum: 1},
                name: {type: "string", minLength: 1}
              },
              required: ["size", "name"]
          end
          stub_const("MyConfig", config_def)

          expect {
            config_def.new(size: 0, name: "test")
          }.to raise_error(Errors::ConfigError, a_string_including("Invalid configuration for `MyConfig` at `test`:", "/size", "minimum"))

          expect {
            config_def.new(size: 10, name: "")
          }.to raise_error(Errors::ConfigError, a_string_including("Invalid configuration for `MyConfig` at `test`:", "/name", "minLength"))

          expect {
            config_def.new(size: 10)
          }.to raise_error(Errors::ConfigError, a_string_including(
            "Invalid configuration for `MyConfig` at `test`:",
            "object at root is missing required properties: name"
          ))
        end

        it "can be defined as a subclass of the class returned by `Config.define`" do
          config_def = ::Class.new(Config.define(:size, :name)) do
            json_schema at: "test", optional: false,
              properties: {
                size: {type: "integer", minimum: 1},
                name: {type: "string", minLength: 1}
              },
              required: ["size", "name"]
          end
          stub_const("MyConfig", config_def)

          valid_config = config_def.new(size: 10, name: "test")

          expect(valid_config.size).to eq(10)
          expect(valid_config.name).to eq("test")
          expect(valid_config).to be_a(::Data)

          expect {
            config_def.new(size: 0, name: "test")
          }.to raise_error(Errors::ConfigError, a_string_including("Invalid configuration for `MyConfig` at `test`:", "/size", "minimum"))
        end

        it "prevents unknown keys since they are likely typos" do
          config_def = Config.define(:size, :name) do
            json_schema at: "test", optional: false,
              properties: {
                size: {type: "integer", minimum: 1},
                name: {type: "string", minLength: 1}
              }
          end

          expect {
            config_def.new(foo: 10, size: 10, name: "foo")
          }.to raise_error(Errors::ConfigError, a_string_including("object property at `/foo` is a disallowed additional property"))
        end

        it "honors defaults specified in the JSON schema" do
          config_def = Config.define(:size, :name) do
            json_schema at: "test", optional: false,
              properties: {
                size: {type: "integer", minimum: 1, default: 7},
                name: {type: "string", minLength: 1, default: "example"}
              }
          end

          config = config_def.new

          expect(config.size).to eq 7
          expect(config.name).to eq "example"
        end

        it "does not allow defaults to violate validations" do
          config_def = Config.define(:size, :name) do
            json_schema at: "test", optional: false,
              properties: {
                size: {type: "integer", minimum: 1, default: 0},
                name: {type: "string", minLength: 1, default: "example"}
              }
          end

          expect {
            config_def.new
          }.to raise_error(Errors::ConfigError, a_string_including("/size", "minimum"))
        end

        context "when the config class defines `convert_values`" do
          login_class = ::Data.define(:username, :password)
          config_class = Config.define(:login, :timeout) do
            json_schema at: "test", optional: false, properties: {
              login: {type: "object"},
              timeout: {type: "number", default: 10}
            }

            define_method :convert_values do |login:, **others|
              {login: login_class.new(**login), **others}
            end
          end

          before do
            stub_const("Login", login_class)
          end

          it "allows the override to convert some config values" do
            config = config_class.new(login: {username: "bob", password: "123"}, timeout: 10)

            expect(config.login).to eq login_class.new(username: "bob", password: "123")
            expect(config.timeout).to eq 10
          end

          it "still validates initialized values" do
            expect {
              config_class.new(login: 5)
            }.to raise_error(Errors::ConfigError, a_string_including("value at `/login` is not an object"))
          end

          it "allows `#with` to carry forward converted values" do
            config = config_class.new(login: {username: "bob", password: "123"}, timeout: 10)
            config.with(timeout: 50)

            expect(config.login).to eq login_class.new(username: "bob", password: "123")
            expect(config.timeout).to eq 10
          end
        end

        describe ".from_parsed_yaml" do
          it "loads from a from parsed YAML hash" do
            config_def = Config.define(:size, :name) do
              json_schema at: "test", optional: false,
                properties: {
                  size: {type: "integer", minimum: 1},
                  name: {type: "string", minLength: 1}
                },
                required: ["size", "name"]
            end

            parsed_yaml = {"test" => {"size" => 5, "name" => "yaml_test"}}
            yaml_config = config_def.from_parsed_yaml(parsed_yaml)

            expect(yaml_config.size).to eq(5)
            expect(yaml_config.name).to eq("yaml_test")
            expect(config_def.from_parsed_yaml!(parsed_yaml)).to eq yaml_config

            parsed_yaml = {"test" => {"size" => 0, "name" => "yaml_test"}}
            expect {
              config_def.from_parsed_yaml(parsed_yaml)
            }.to raise_error(Errors::ConfigError, a_string_including("/size", "minimum"))
          end

          it "returns `nil` if the parsed YAML hash has no entry at the specified path" do
            config_def = Config.define(:size, :name) do
              json_schema at: "test", optional: false,
                properties: {
                  size: {type: "integer", minimum: 1},
                  name: {type: "string", minLength: 1}
                },
                required: ["size", "name"]
            end

            expect(config_def.from_parsed_yaml({})).to eq nil
          end

          it "raises from `from_parsed_yaml!` if the parsed YAML hash has no entry at the specified path" do
            config_def = Config.define(:size, :name) do
              json_schema at: "test", optional: false,
                properties: {
                  size: {type: "integer", minimum: 1},
                  name: {type: "string", minLength: 1}
                },
                required: ["size", "name"]
            end
            stub_const("MyConfig", config_def)

            expect {
              config_def.from_parsed_yaml!({})
            }.to raise_error(Errors::ConfigError, "Invalid configuration for `MyConfig` at `test`: missing configuration at `test`.")
          end

          it "extracts config data from nested YAML structure" do
            config_def = Config.define(:database_url, :pool_size) do
              json_schema at: "database.connection", optional: false,
                properties: {
                  database_url: {type: "string", minLength: 1},
                  pool_size: {type: "integer", minimum: 1}
                },
                required: ["database_url", "pool_size"]
            end

            nested_yaml = {
              "database" => {
                "connection" => {
                  "database_url" => "postgres://localhost/test",
                  "pool_size" => 5
                }
              }
            }

            config = config_def.from_parsed_yaml(nested_yaml)
            expect(config.database_url).to eq("postgres://localhost/test")
            expect(config.pool_size).to eq(5)
          end

          it "does not symbolize string keys on map values" do
            config_def = Config.define(:thresholds_by_name) do
              json_schema at: "test", optional: false,
                properties: {
                  thresholds_by_name: {type: "object", patternProperties: {
                    /^\w+$/.source => {type: "integer"}
                  }}
                }
            end

            config = config_def.from_parsed_yaml({"test" => {"thresholds_by_name" => {"foo" => 10, "bar" => 12}}})

            expect(config.thresholds_by_name).to eq({
              "foo" => 10,
              "bar" => 12
            })
          end

          it "raises a clear error if the value at the specified path is not a hash" do
            config_def = Config.define(:size, :name) do
              json_schema at: "test", optional: false,
                properties: {
                  size: {type: "integer", minimum: 1},
                  name: {type: "string", minLength: 1}
                },
                required: ["size", "name"]
            end
            stub_const("MyConfig", config_def)

            expect {
              config_def.from_parsed_yaml({"test" => 10})
            }.to raise_error(Errors::ConfigError, "Invalid configuration for `MyConfig` at `test`: Expected a hash at `test`, got: `10`.")
          end
        end

        context "YAML file integration", :in_temp_dir do
          it "loads configuration from YAML file" do
            config_def = Config.define(:host, :port) do
              json_schema at: "server", optional: false,
                properties: {
                  host: {type: "string", minLength: 1},
                  port: {type: "integer", minimum: 1, maximum: 65535}
                },
                required: ["host", "port"]
            end

            yaml_content = {
              "server" => {
                "host" => "localhost",
                "port" => 3000
              }
            }

            ::File.write("config.yaml", ::YAML.dump(yaml_content))
            config = config_def.from_yaml_file("config.yaml")

            expect(config.host).to eq("localhost")
            expect(config.port).to eq(3000)
          end

          it "returns `nil` if the YAML file has no entry at the specified path" do
            config_def = Config.define(:host, :port) do
              json_schema at: "server", optional: false,
                properties: {
                  host: {type: "string", minLength: 1},
                  port: {type: "integer", minimum: 1, maximum: 65535}
                },
                required: ["host", "port"]
            end

            yaml_content = {
              "other" => {
                "host" => "localhost",
                "port" => 3000
              }
            }

            ::File.write("config.yaml", ::YAML.dump(yaml_content))
            config = config_def.from_yaml_file("config.yaml")

            expect(config).to be nil
          end

          it "supports YAML file with block for preprocessing" do
            config_def = Config.define(:name, :env) do
              json_schema at: "app", optional: false,
                properties: {
                  name: {type: "string"},
                  env: {type: "string", enum: ["development", "test", "production"]}
                },
                required: ["name", "env"]
            end

            yaml_content = {
              "app" => {
                "name" => "test_app",
                "env" => "development"
              }
            }

            ::File.write("config.yaml", ::YAML.dump(yaml_content))

            # Test with preprocessing block
            config = config_def.from_yaml_file("config.yaml") do |parsed_yaml|
              # Modify the environment in preprocessing
              parsed_yaml["app"]["env"] = "test"
              parsed_yaml
            end

            expect(config.name).to eq("test_app")
            expect(config.env).to eq("test") # Modified by preprocessing block
          end
        end
      end
    end
  end
end
