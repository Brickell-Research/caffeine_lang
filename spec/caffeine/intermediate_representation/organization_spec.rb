# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::Organization do
  let(:teams) { [] }
  let(:service_definitions) { [] }
  let(:organization) { described_class.new(teams, service_definitions) }

  describe '#initialize' do
    context 'when empty organization is provided' do
      it 'successfully reads the teams' do
        expect(organization.teams).to eq(teams)
      end

      it 'successfully reads the service definitions' do
        expect(organization.service_definitions).to eq(service_definitions)
      end
    end
  end
end
