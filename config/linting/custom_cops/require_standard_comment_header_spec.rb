# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "require_standard_comment_header"
require "rubocop/rspec/support"
require "date"

module ElasticGraph
  RSpec.describe RequireStandardCommentHeader do
    include ::RuboCop::RSpec::ExpectOffense

    let(:cop) { RequireStandardCommentHeader.new(config) }
    let(:config) { ::RuboCop::Config.new("ElasticGraph/RequireStandardCommentHeader" => {"Enabled" => true}) }
    let(:current_year) { Date.today.year }
    let(:year_range) { "2024 - #{current_year}" }

    it "autocorrects a file that does not have the standard header" do
      expect_offense(<<~RUBY)
        module MyClass
        ^^^^^^^^^^^^^^ Missing standard comment header at top of file.
        end
      RUBY

      expect_correction(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        module MyClass
        end
      RUBY
    end

    it "does not register an offense when a file has the standard header (and no other leading comments)" do
      expect_no_offenses(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        module MyClass
        end
      RUBY
    end

    it "autocorrects a file when the class documentation has no blank line between it and the standard header" do
      expect_offense(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Standard header is out of date.
        # Some documentation for my class.
        module MyClass
        end
      RUBY

      expect_correction(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        # Some documentation for my class.
        module MyClass
        end
      RUBY
    end

    it "does not register an offense when a file has the standard header and other leading comments with a blank line in between" do
      expect_no_offenses(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        # Some documentation for my class.
        module MyClass
        end
      RUBY
    end

    it "autocorrects a file that is only comments but lacks the standard header" do
      expect_offense(<<~RUBY)
        # This is a placeholder file.
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Missing standard comment header at top of file.
        # It has some comments.
      RUBY

      expect_correction(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        # This is a placeholder file.
        # It has some comments.
      RUBY
    end

    it "does not register an offense when a file is only comments and has the standard header" do
      expect_no_offenses(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        # This is a placeholder file.
        # It has some comments.
      RUBY
    end

    it "autocorrects a comments-only file when the non-standard comments have no blank comment line between them and the standard header" do
      expect_offense(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Standard header is out of date.
        # This is a placeholder file.
        # It has some comments.
      RUBY

      expect_correction(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        # This is a placeholder file.
        # It has some comments.
      RUBY
    end

    it "autocorrects an out-of-date standard header" do
      expect_offense(<<~RUBY)
        # Copyright 2024 Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Standard header is out of date.

        module MyClass
        end
      RUBY

      expect_correction(<<~RUBY)
        # Copyright #{year_range} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

        module MyClass
        end
      RUBY
    end

    it "leaves a file with a shebang line unchanged even if it lacks the standard header since adding it above the shebang would break the script" do
      expect_no_offenses(<<~RUBY)
        #!/usr/bin/env ruby

        puts "hello world"
      RUBY
    end

    describe "LICENSE.txt" do
      let(:expected_copyright) { "Copyright (c) 2024 - #{current_year} Block, Inc." }

      it "has an up-to-date copyright notice" do
        license_content = File.read(File.expand_path("../../../LICENSE.txt", __dir__))
        copyright_line = license_content.lines.find { |line| line.include?("Copyright") }.to_s.strip

        expect(copyright_line).to eq(expected_copyright)
      end
    end
  end
end
