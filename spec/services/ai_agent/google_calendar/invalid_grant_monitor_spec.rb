require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::InvalidGrantMonitor do
  let(:account)   { create(:account) }
  let(:ai_agent)  { create(:ai_agent, account: account, name: 'Julia') }
  let(:other_agent) { create(:ai_agent, account: account, name: 'Nilda') }

  before do
    Rails.cache.clear
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  it 'não alerta antes de bater o threshold' do
    99.times { described_class.track!(ai_agent) }
    expect(Rails.logger).not_to have_received(:warn).with(/needs re-authorization/)
  end

  it 'alerta assim que bate o threshold (100 falhas na janela)' do
    100.times { described_class.track!(ai_agent) }
    expect(Rails.logger).to have_received(:warn).with(/OAuth needs re-authorization for agent Julia/).once
  end

  it 'não repete o alerta na mesma janela de debounce, mesmo com mais falhas' do
    150.times { described_class.track!(ai_agent) }
    expect(Rails.logger).to have_received(:warn).with(/needs re-authorization/).once
  end

  it 'conta falhas de agentes diferentes de forma independente' do
    99.times { described_class.track!(ai_agent) }
    described_class.track!(other_agent)

    expect(Rails.logger).not_to have_received(:warn).with(/needs re-authorization/)
  end

  it 'não quebra quando o agent é nil' do
    expect { described_class.track!(nil) }.not_to raise_error
  end
end
