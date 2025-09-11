# frozen_string_literal: true
# typed: strict

module Caffeine
  # From RFC-001:
  # enum AcceptedType = Boolean | Decimal | Integer | List<AcceptedTypes> | String
  module IntermediateRepresentation
    extend T::Sig

    AcceptedType = T.type_alias do
      T.any(
        T::Boolean, BigDecimal, Integer, String,
        # unsure how to do a single level recursive type alias
        T::Array[T::Boolean],
        T::Array[BigDecimal],
        T::Array[Integer],
        T::Array[String]
      )
    end
  end
end
