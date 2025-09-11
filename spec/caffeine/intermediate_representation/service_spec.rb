# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::Service do
  let(:service_name) { 'Authentication Service' }
  let(:supported_slos_types) { [] }
  let(:service) { described_class.new(service_name, supported_slos_types) }

  describe '#initialize' do
    context 'when empty service is provided' do
      it 'successfully reads the service name' do
        expect(service.name).to eq(service_name)
      end

      it 'successfully reads the supported SLO types' do
        expect(service.supported_slos_types).to eq(supported_slos_types)
      end
    end
  end
end
