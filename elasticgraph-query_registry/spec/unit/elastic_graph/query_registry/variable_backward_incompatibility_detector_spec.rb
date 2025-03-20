# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/query_registry/variable_backward_incompatibility_detector"

module ElasticGraph
  module QueryRegistry
    RSpec.describe VariableBackwardIncompatibilityDetector, ".detect" do
      let(:variable_backward_incompatibility_detector) { VariableBackwardIncompatibilityDetector.new }

      it "returns an empty list when given two empty hashes" do
        incompatibilities = detect_incompatibilities(
          old: {},
          new: {}
        )

        expect(incompatibilities).to eq([])
      end

      it "returns an empty list when given identical variables" do
        incompatibilities = detect_incompatibilities(
          old: {"id" => "ID!", "count" => "Int"},
          new: {"id" => "ID!", "count" => "Int"}
        )

        expect(incompatibilities).to eq([])
      end

      it "identifies a removed variable, regardless of nullability, as potentially breaking since the client may pass a value for it" do
        incompatibilities = detect_incompatibilities(
          old: {"id" => "ID!", "count" => "Int", "foo" => "Int!"},
          new: {"id" => "ID!"}
        )

        expect(incompatibilities).to contain_exactly(
          "$count (removed)",
          "$foo (removed)"
        )
      end

      it "identifies an added variable as potentially breaking only if it is non-null since the client isn't passing a value for it and that causes no problem for nullable vars" do
        incompatibilities = detect_incompatibilities(
          old: {"id" => "ID!"},
          new: {
            "id" => "ID!",
            "count" => "Int",
            "foo" => "Int!",
            "new_enum1" => {
              "type" => "Enum1",
              "values" => ["A"]
            },
            "new_enum2" => {
              "type" => "Enum1!",
              "values" => ["A"]
            },
            "new_object1" => {
              "type" => "Object1",
              "fields" => {
                "foo" => "Int"
              }
            },
            "new_object2" => {
              "type" => "Object1!",
              "fields" => {
                "foo" => "Int"
              }
            }
          }
        )

        expect(incompatibilities).to contain_exactly(
          "$foo (new required variable)",
          "$new_enum2 (new required variable)",
          "$new_object2 (new required variable)"
        )
      end

      it "identifies a variable with a changed type to be potentially breaking unless its only relaxing nullability" do
        incompatibilities = detect_incompatibilities(
          old: {"id" => "ID!", "count" => "Int", "foo" => "String", "bar" => "Float"},
          new: {"id" => "ID", "count" => "Int!", "foo" => "Int", "bar" => "Int!"}
        )

        expect(incompatibilities).to contain_exactly(
          "$count (required for the first time)",
          "$foo (type changed from `String` to `Int`)",
          "$bar (type changed from `Float` to `Int!`)"
        )
      end

      it "handles a variable changing to an enum type or from an enum type" do
        incompatibilities = detect_incompatibilities(
          old: {
            "var1" => {
              "type" => "Enum1",
              "values" => ["A", "B", "C"]
            },
            "var2" => "Int"
          },
          new: {
            "var1" => "Int",
            "var2" => {
              "type" => "Enum1",
              "values" => ["A", "B", "C"]
            }
          }
        )

        expect(incompatibilities).to contain_exactly(
          "$var1 (type changed from `Enum1` to `Int`)",
          "$var2 (type changed from `Int` to `Enum1`)"
        )
      end

      it "handles a variable changing to an object type or from an object type" do
        incompatibilities = detect_incompatibilities(
          old: {
            "var1" => {
              "type" => "Object1",
              "fields" => {
                "foo" => "Int"
              }
            },
            "var2" => "Int"
          },
          new: {
            "var1" => "Int",
            "var2" => {
              "type" => "Object1",
              "fields" => {
                "foo" => "Int"
              }
            }
          }
        )

        expect(incompatibilities).to contain_exactly(
          "$var1 (type changed from `Object1` to `Int`)",
          "$var2 (type changed from `Int` to `Object1`)"
        )
      end

      context "with an enum variable" do
        it "does not consider it breaking when the enum values have not changed" do
          incompatibilities = detect_incompatibilities(
            old: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C"]
              }
            },
            new: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C"]
              }
            }
          )

          expect(incompatibilities).to eq([])
        end

        it "identifies the variable as potentially breaking when it loses an enum value that the client could depend on" do
          incompatibilities = detect_incompatibilities(
            old: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C", "D"]
              }
            },
            new: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "C"]
              }
            }
          )

          expect(incompatibilities).to contain_exactly("$enum1 (removed enum values: B, D)")
        end

        it "ignores new enum values since the client can't be broken by an input enum type accepting a new value" do
          incompatibilities = detect_incompatibilities(
            old: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C"]
              }
            },
            new: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C", "D"]
              }
            }
          )

          expect(incompatibilities).to eq([])
        end

        it "identifies the variable as potentially breaking when it both gains and loses enum values" do
          incompatibilities = detect_incompatibilities(
            old: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "B", "C"]
              }
            },
            new: {
              "enum1" => {
                "type" => "Enum1",
                "values" => ["A", "D", "C"]
              }
            }
          )

          expect(incompatibilities).to contain_exactly("$enum1 (removed enum values: B)")
        end
      end

      context "with object variables" do
        it "does not consider it breaking when the object fields have not changed" do
          incompatibilities = detect_incompatibilities(
            old: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int"
                }
              }
            },
            new: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int"
                }
              }
            }
          )

          expect(incompatibilities).to eq([])
        end

        it "identifies the variable as potentially breaking when it loses fields that the client could depend on" do
          incompatibilities = detect_incompatibilities(
            old: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int"
                }
              }
            },
            new: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int"
                }
              }
            }
          )

          expect(incompatibilities).to contain_exactly("$object1.bar (removed)")
        end

        it "identifies the variable as potentially breaking when it gains a non-null field, since the client couldn't already be passing values for it" do
          incompatibilities = detect_incompatibilities(
            old: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int"
                }
              }
            },
            new: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int",
                  "bazz" => "Int!"
                }
              }
            }
          )

          expect(incompatibilities).to contain_exactly("$object1.bazz (new required field)")
        end

        it "ignores new nullable fields since the client can't be broken by the endpoint optionally accepting a field the client doesn't know about" do
          incompatibilities = detect_incompatibilities(
            old: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int"
                }
              }
            },
            new: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo" => "Int",
                  "bar" => "Int",
                  "bazz" => "Int"
                }
              }
            }
          )

          expect(incompatibilities).to eq([])
        end

        it "detects incompatibilities for nested fields" do
          incompatibilities = detect_incompatibilities(
            old: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo1" => {
                    "type" => "Object2",
                    "fields" => {
                      "foo2" => {
                        "type" => "Object3",
                        "fields" => {
                          "foo3" => "Int",
                          "foo4" => "Int"
                        }
                      }
                    }
                  }
                }
              }
            },
            new: {
              "object1" => {
                "type" => "Object1",
                "fields" => {
                  "foo1" => {
                    "type" => "Object2",
                    "fields" => {
                      "foo2" => {
                        "type" => "Object3",
                        "fields" => {
                          "foo3" => "Int"
                        }
                      }
                    }
                  }
                }
              }
            }
          )

          expect(incompatibilities).to contain_exactly("$object1.foo1.foo2.foo4 (removed)")
        end
      end

      def detect_incompatibilities(old:, new:)
        variable_backward_incompatibility_detector.detect(old_op_vars: old, new_op_vars: new).map(&:description)
      end
    end
  end
end
