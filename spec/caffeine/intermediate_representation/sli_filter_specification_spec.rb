# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::SLIFilterSpecification do
  let(:attribute_name) { 'status_code' }
  let(:attribute_type) { 'String' }
  let(:required) { true }
  let(:filter_spec) { described_class.new(attribute_name, attribute_type, required) }

  describe '#initialize' do
    context 'when simple filter specification is provided' do
      it 'successfully reads the attribute name' do
        expect(filter_spec.attribute_name).to eq(attribute_name)
      end

      it 'successfully reads the attribute type' do
        expect(filter_spec.attribute_type).to eq(attribute_type)
      end

      it 'successfully reads the required flag' do
        expect(filter_spec.required).to eq(required)
      end
    end
  end
end
