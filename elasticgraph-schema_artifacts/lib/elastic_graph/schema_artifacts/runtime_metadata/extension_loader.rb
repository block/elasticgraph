# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Responsible for loading extensions. This loader requires an interface definition
      # (a class or module with empty method definitions that just serves to define what
      # loaded extensions must implement). That allows us to verify the extension implements
      # the interface correctly at load time, rather than deferring exceptions to when the
      # extension is later used.
      #
      # Note, however, that this does not guarantee no runtime exceptions from the use of the
      # extension: the extension may return invalid return values, or throw exceptions when
      # called. But this verifies the interface to the extent that we can.
      class ExtensionLoader
        def initialize(interface_def)
          @interface_def = interface_def
          @loaded_by_name = {}
        end

        # Loads the extension using the provided constant name, after requiring the `from` path.
        # Memoizes the result.
        def load(constant_name, from:, config:)
          (@loaded_by_name[constant_name] ||= load_extension(constant_name, from)).tap do |extension|
            if extension.require_path != from
              raise Errors::InvalidExtensionError, "Extension `#{constant_name}` cannot be loaded from `#{from}`, " \
                "since it has already been loaded from `#{extension.require_path}`."
            end
          end.with(extension_config: config)
        end

        private

        def load_extension(constant_name, require_path)
          require require_path
          extension_class = ::Object.const_get(constant_name).tap { |ext| verify_interface(constant_name, ext) }
          Extension.new(extension_class, require_path, {})
        end

        def verify_interface(constant_name, extension)
          # @type var problems: ::Array[::String]
          problems = []
          problems.concat(verify_methods("class", extension.singleton_class, @interface_def.singleton_class))

          if extension.is_a?(::Module)
            problems.concat(verify_methods("instance", extension, @interface_def))

            # We care about the name exactly matching so that we can dump the extension name in a schema
            # artifact w/o having to pass around the original constant name.
            if extension.name != constant_name.delete_prefix("::")
              problems << "- Exposes a name (`#{extension.name}`) that differs from the provided extension name (`#{constant_name}`)"
            end
          else
            problems << "- Is not a class or module as expected"
          end

          if problems.any?
            raise Errors::InvalidExtensionError,
              "Extension `#{constant_name}` does not implement the expected interface correctly. Problems:\n\n" \
              "#{problems.join("\n")}"
          end
        end

        def verify_methods(type, extension, interface)
          interface_methods = list_instance_interface_methods(interface)
          extension_methods = list_instance_interface_methods(extension)

          # @type var problems: ::Array[::String]
          problems = []

          if (missing_methods = interface_methods - extension_methods).any?
            problems << "- Missing #{type} methods: #{missing_methods.map { |m| "`#{m}`" }.join(", ")}"
          end

          interface_methods.intersection(extension_methods).each do |method_name|
            unless parameters_match?(extension, interface, method_name)
              interface_signature = signature_code_for(interface, method_name)
              extension_signature = signature_code_for(extension, method_name)

              problems << "- Method signature for #{type} method `#{method_name}` (`#{extension_signature}`) does not match interface (`#{interface_signature}`)"
            end
          end

          problems
        end

        def list_instance_interface_methods(klass)
          # Here we look at more than just the public methods. This is necessary for `initialize`.
          # If it's defined on the interface definition, we want to verify it on the extension,
          # but Ruby makes `initialize` private by default.
          klass.instance_methods(false) +
            klass.protected_instance_methods(false) +
            klass.private_instance_methods(false)
        end

        def parameters_match?(extension, interface, method_name)
          interface_parameters = interface.instance_method(method_name).parameters
          extension_parameters = extension.instance_method(method_name).parameters

          # Here we compare the parameters for exact equality. This is stricter than we need it
          # to be (it doesn't allow the parameters to have different names, for example) but it's
          # considerably simpler than us trying to determine what is truly required. For example,
          # the name doesn't matter on a positional arg, but would matter on a keyword arg.
          interface_parameters == extension_parameters
        end

        def signature_code_for(object, method_name)
          # @type var file_name: ::String?
          # @type var line_number: ::Integer?
          file_name, line_number = object.instance_method(method_name).source_location
          ::File.read(file_name.to_s).split("\n").fetch(line_number.to_i - 1).strip
        end
      end
    end
  end
end
