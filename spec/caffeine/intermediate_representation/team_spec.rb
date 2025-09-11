# frozen_string_literal: true

RSpec.describe Caffeine::IntermediateRepresentation::Team do
  let(:team_name) { 'Team 1' }
  let(:team_without_slos) { described_class.new(team_name, []) }

  describe '#initialize' do
    context 'when no slos are provided' do
      it 'successfully reads the team name' do
        expect(team_without_slos.name).to eq(team_name)
      end

      it 'successfully reads the team slos' do
        expect(team_without_slos.slos).to be_empty
      end
    end
  end
end
