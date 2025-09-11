# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::SLO do
  let(:filters) { { 'filter_1' => 'value_1' } }
  let(:threshold) { 0.95 }
  let(:slo_type) { Caffeine::IntermediateRepresentation::SLOType.new([], 'Some SLO Type', 'query template') }
  let(:slo) { described_class.new(filters, threshold, slo_type) }

  describe '#initialize' do
    context 'when simple, single filter SLO is provided' do
      it 'successfully reads the filters' do
        expect(slo.filters).to eq(filters)
      end

      it 'successfully reads the threshold' do
        expect(slo.threshold).to eq(threshold)
      end

      it 'successfully reads the slo type' do
        expect(slo.slo_type).to eq(slo_type)
      end
    end
  end
end
