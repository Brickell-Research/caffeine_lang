# frozen_string_literal: true
# typed: strict

module Caffeine
  module IntermediateRepresentation
    # From RFC-001:
    # type Organization = {
    #   teams: List<Team>,
    #   service_definitions: List<Service>
    # }
    class Organization < BaseNode
      extend T::Sig

      sig { returns(T::Array[Team]) }
      attr_accessor :teams

      sig { returns(T::Array[Service]) }
      attr_accessor :service_definitions

      sig { params(teams: T.untyped, service_definitions: T.untyped).void }
      def initialize(teams, service_definitions)
        @teams = T.let(teams, T::Array[Team])
        @service_definitions = T.let(service_definitions, T::Array[Service])

        super()
      end
    end
  end
end
