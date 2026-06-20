require 'rails_helper'

RSpec.describe AiAgent::NativeToolRegistry do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  describe '.activate' do
    it 'cria as 3 tools nativas de google_calendar' do
      tools = described_class.activate(ai_agent, 'google_calendar')
      expect(tools.size).to eq(3)
      expect(ai_agent.tools.native.pluck(:native_key)).to contain_exactly(
        'gcal_consultar_horarios_livres', 'gcal_criar_agendamento', 'gcal_cancelar_agendamento'
      )
    end

    it 'marca is_native, active e injeta o header de token interno como referência ENV' do
      described_class.activate(ai_agent, 'google_calendar')
      tool = ai_agent.tools.find_by(native_key: 'gcal_criar_agendamento')
      expect(tool.is_native).to be(true)
      expect(tool.active).to be(true)
      expect(tool.headers['X-Internal-Token']).to eq('${INTERNAL_API_TOKEN}')
      expect(tool.endpoint_url).to include("/api/v1/accounts/#{account.id}/ai_agent_calendar/criar_agendamento")
      expect(tool.endpoint_url).to include("ai_agent_id=#{ai_agent.id}")
    end

    it 'NÃO expõe lead_phone nem event_id nos schemas (privacidade)' do
      described_class.activate(ai_agent, 'google_calendar')
      ai_agent.tools.native.each do |tool|
        props = tool.parameters_schema['properties'].keys
        expect(props).not_to include('lead_phone', 'event_id')
      end
    end

    it 'é idempotente — rodar de novo não duplica' do
      described_class.activate(ai_agent, 'google_calendar')
      expect { described_class.activate(ai_agent, 'google_calendar') }
        .not_to change { ai_agent.tools.native.count }
      expect(ai_agent.tools.native.count).to eq(3)
    end

    it 'reativa tools que estavam inativas' do
      described_class.activate(ai_agent, 'google_calendar')
      ai_agent.tools.native.update_all(active: false)
      described_class.activate(ai_agent, 'google_calendar')
      expect(ai_agent.tools.native.where(active: true).count).to eq(3)
    end
  end

  describe '.deactivate' do
    it 'desativa as tools nativas sem deletar' do
      described_class.activate(ai_agent, 'google_calendar')
      described_class.deactivate(ai_agent, 'google_calendar')
      expect(ai_agent.tools.native.where(active: true).count).to eq(0)
      expect(ai_agent.tools.native.count).to eq(3)
    end
  end
end
