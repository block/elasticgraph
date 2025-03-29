# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Responsible for verifying extensions. This requires an interface definition
      # (a class or module with empty method definitions that just serves to define what
      # loaded extensions must implement). That allows us to verify the extension implements
      # the interface correctly ahead of time, rather than deferring exceptions to when the
      # extension is later used.
      #
      # Note, however, that this does not guarantee no runtime exceptions from the use of the
      # extension: the extension may return invalid return values, or throw exceptions when
      # called. But this verifies the interface to the extent that we can.
      module InterfaceVerifier
        class << self
          def verify!(extension, against:, constant_name:)
            problems = verify(extension, against:, constant_name:)

            if problems.any?
              raise Errors::InvalidExtensionError,
                "Extension `#{constant_name}` does not implement the expected interface correctly. Problems:\n\n" \
                "#{problems.join("\n")}"
            end
          end

          def verify(extension, against:, constant_name:)
            problems = [] # : ::Array[::String]
            problems.concat(verify_methods("class", extension.singleton_class, against.singleton_class))

            if extension.is_a?(::Module)
              problems.concat(verify_methods("instance", extension, against))

              # We care about the name exactly matching so that we can dump the extension name in a schema
              # artifact w/o having to pass around the original constant name.
              if extension.name != constant_name.delete_prefix("::")
                problems << "- Exposes a name (`#{extension.name}`) that differs from the provided extension name (`#{constant_name}`)"
              end
            else
              problems << "- Is not a class or module as expected"
            end

            problems
          end

          private

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
end
