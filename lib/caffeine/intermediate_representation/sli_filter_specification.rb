# frozen_string_literal: true
# typed: strict

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type SLIFilterSpecification = {
    #   attribute_name: String,
    #   attribute_type: AcceptedType,
    #   required: Boolean
    # }
    class SLIFilterSpecification < BaseNode
      extend T::Sig

      sig { returns(String) }
      attr_accessor :attribute_name

      sig { returns(AcceptedType) }
      attr_accessor :attribute_type

      sig { returns(T::Boolean) }
      attr_accessor :required

      sig { params(attribute_name: T.untyped, attribute_type: T.untyped, required: T.untyped).void }
      def initialize(attribute_name, attribute_type, required)
        @attribute_name = T.let(attribute_name, String)
        @attribute_type = T.let(attribute_type, AcceptedType)
        @required = T.let(required, T::Boolean)

        super()
      end
    end
  end
end
