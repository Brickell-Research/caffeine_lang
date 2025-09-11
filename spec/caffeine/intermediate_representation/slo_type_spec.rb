# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::SLOType do
  let(:filters) { [] }
  let(:name) { 'HTTP Success Rate' }
  let(:query_template) { 'SELECT success_rate FROM metrics WHERE service = ?' }
  let(:slo_type) { described_class.new(filters, name, query_template) }

  describe '#initialize' do
    context 'when simple SLO type is provided' do
      it 'successfully reads the filters' do
        expect(slo_type.filters).to eq(filters)
      end

      it 'successfully reads the name' do
        expect(slo_type.name).to eq(name)
      end

      it 'successfully reads the query template' do
        expect(slo_type.query_template).to eq(query_template)
      end
    end
  end
end
