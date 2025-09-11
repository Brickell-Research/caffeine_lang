# frozen_string_literal: true
# typed: strict

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type SLOType = {
    #   filters: List<SLIFilterSpecification>,
    #   name: String,
    #   query_template: String
    # }
    class SLOType < BaseNode
      extend T::Sig

      sig { returns(T::Array[SLIFilterSpecification]) }
      attr_accessor :filters

      sig { returns(String) }
      attr_accessor :name

      sig { returns(String) }
      attr_accessor :query_template

      sig { params(filters: T.untyped, name: T.untyped, query_template: T.untyped).void }
      def initialize(filters, name, query_template)
        @filters = T.let(filters, T::Array[SLIFilterSpecification])
        @name = T.let(name, String)
        @query_template = T.let(query_template, String)

        super()
      end
    end
  end
end
