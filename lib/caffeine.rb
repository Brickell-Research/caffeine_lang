# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'caffeine/version'
require_relative 'caffeine/intermediate_representation/base_node'
require_relative 'caffeine/intermediate_representation/accepted_type'
require_relative 'caffeine/intermediate_representation/sli_filter_specification'
require_relative 'caffeine/intermediate_representation/slo_type'
require_relative 'caffeine/intermediate_representation/slo'
require_relative 'caffeine/intermediate_representation/service'
require_relative 'caffeine/intermediate_representation/team'
require_relative 'caffeine/intermediate_representation/organization'

# main module
module Caffeine
  extend T::Sig

  class Error < StandardError; end

  # Intermediate representation
  module IntermediateRepresentation
    autoload :BaseNode, 'caffeine/intermediate_representation/base_node'
    autoload :Organization, 'caffeine/intermediate_representation/organization'
    autoload :Service, 'caffeine/intermediate_representation/service'
    autoload :SLI, 'caffeine/intermediate_representation/sli'
    autoload :SLIFilterSpecification, 'caffeine/intermediate_representation/sli_filter_specification'
    autoload :SLO, 'caffeine/intermediate_representation/slo'
    autoload :SLOType, 'caffeine/intermediate_representation/slo_type'
    autoload :Team, 'caffeine/intermediate_representation/team'
  end
end
