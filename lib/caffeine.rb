# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'caffeine/version'

# main module
module Caffeine
  extend T::Sig

  class Error < StandardError; end
end
