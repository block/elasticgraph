# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

class FallbackSnippetValidator < SnippetValidator
  def validate(snippet)
    ValidationResult.failed("Snippet type `#{snippet.type}` is not yet supported by the validation script. Consider adding a validator for this type.")
  end
end
