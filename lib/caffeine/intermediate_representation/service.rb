# frozen_string_literal: true
# typed: strict

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type Service = {
    #   name: String,
    #   supported_slos_types: List<SLOType>
    # }
    class Service < BaseNode
      extend T::Sig

      sig { returns(String) }
      attr_accessor :name

      sig { returns(T::Array[SLOType]) }
      attr_accessor :supported_slos_types

      sig { params(name: T.untyped, supported_slos_types: T.untyped).void }
      def initialize(name, supported_slos_types)
        @name = T.let(name, String)
        @supported_slos_types = T.let(supported_slos_types, T::Array[SLOType])

        super()
      end
    end
  end
end
