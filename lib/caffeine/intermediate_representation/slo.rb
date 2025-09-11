# frozen_string_literal: true
# typed: strict

require 'bigdecimal'

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type SLO = {
    #   filters: Map<String, AcceptedType>,
    #   threshold: Decimal,
    #   slo_type: SLOType
    # }
    class SLO < BaseNode
      extend T::Sig

      sig { returns(T::Hash[String, T.untyped]) }
      attr_accessor :filters

      sig { returns(BigDecimal) }
      attr_accessor :threshold

      sig { returns(SLOType) }
      attr_accessor :slo_type

      sig { params(filters: T.untyped, threshold: T.untyped, slo_type: T.untyped).void }
      def initialize(filters, threshold, slo_type)
        @filters = T.let(filters, T::Hash[String, T.untyped])
        @threshold = T.let(BigDecimal(threshold.to_s), BigDecimal)
        @slo_type = T.let(slo_type, SLOType)

        super()
      end
    end
  end
end
