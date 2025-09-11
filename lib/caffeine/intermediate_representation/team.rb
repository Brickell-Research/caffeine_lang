# frozen_string_literal: true
# typed: strict

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type Team = {
    #   name: String,
    #   slos: List<SLO>
    # }
    class Team < BaseNode
      extend T::Sig

      sig { returns(String) }
      attr_accessor :name

      sig { returns(T::Array[SLO]) }
      attr_accessor :slos

      sig { params(name: T.untyped, slos: T.untyped).void }
      def initialize(name, slos)
        @name = T.let(name, String)
        @slos = T.let(slos, T::Array[SLO])

        super()
      end
    end
  end
end
