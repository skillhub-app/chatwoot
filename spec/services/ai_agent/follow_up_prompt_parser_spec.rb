# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::FollowUpPromptParser do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:contact)      { create(:contact, account: account, name: 'Rita', phone_number: '+5591985740371') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:stage)        { double('KanbanStage', name: 'Qualificação') }

  before { allow(AiAgent::IncomingMessageProcessor).to receive(:call) }

  def parser(input, mode_override: nil)
    described_class.new(
      input,
      contact:       contact,
      conversation:  conversation,
      stage:         stage,
      mode_override: mode_override
    )
  end

  describe '#detected_mode (auto-detect)' do
    it 'verbo comando → :command' do
      expect(parser('Analise as últimas mensagens e escreva um follow-up').detected_mode).to eq(:command)
    end

    it 'texto livre → :template' do
      expect(parser('Olá, tudo bem? Ainda pensando na proposta?').detected_mode).to eq(:template)
    end

    it '"Com base no que vimos" → :command' do
      expect(parser('Com base no que vimos, escreva uma mensagem de retomada').detected_mode).to eq(:command)
    end

    it 'override="template" com input de comando → :template' do
      expect(parser('Gere uma mensagem urgente', mode_override: 'template').detected_mode).to eq(:template)
    end

    it 'override="command" com texto livre → :command' do
      expect(parser('Olá, como vai?', mode_override: 'command').detected_mode).to eq(:command)
    end
  end

  describe '#call — interpolação de variáveis' do
    it 'interpola {{nome}} com contact.name' do
      result = parser('Oi {{nome}}, tudo bem?').call
      expect(result).to include('Rita')
    end

    it 'interpola [nome] com contact.name' do
      result = parser('Oi [nome], tudo bem?').call
      expect(result).to include('Rita')
    end

    it 'interpola variável com contact nil → string vazia' do
      p = described_class.new('Oi {{nome}}', contact: nil, conversation: conversation, stage: nil)
      expect(p.call).to include('Oi ')
      expect(p.call).not_to include('{{nome}}')
    end
  end

  # v66 (Fix B): o prompt passou a usar tags XML em vez de cabeçalhos "## ..."
  # (que o LLM ecoava) e a carregar regras de saída explícitas.
  describe '#call — build_template_prompt (v66: XML tags)' do
    subject(:result) { parser('Oi, passando para ver como está.').call }

    it 'usa delimitadores XML em vez de cabeçalhos "##"' do
      expect(result).to include('<exemplo_de_mensagem>')
      expect(result).to include('<contexto_recente>')
      expect(result).to include('<instrucao>')
      expect(result).not_to include('Exemplo de mensagem:')
      expect(result).not_to match(/^\s*##\s/)
    end

    it 'inclui regras críticas de saída (não copiar / sem markdown)' do
      expect(result).to match(/N[ÃA]O copie esta instru/i)
      expect(result).to match(/APENAS o texto da mensagem/i)
    end
  end

  describe '#call — build_command_prompt (v66: XML tags)' do
    subject(:result) { parser('Analise o contexto e escreva uma mensagem de follow-up').call }

    it 'usa <instrucao_operador> em vez de cabeçalho "Instrução:"' do
      expect(result).to include('<instrucao_operador>')
      expect(result).to include('<instrucao>')
      expect(result).not_to match(/^\s*##\s/)
    end
  end

  describe '#recent_messages_text' do
    before do
      create(:message, conversation: conversation, message_type: :incoming, content: 'Mensagem do cliente')
      create(:message, conversation: conversation, message_type: :outgoing, content: 'Resposta da Julia')
    end

    it 'retorna mensagens recentes ordenadas em ASC' do
      p = parser('Gere um follow-up')
      text = p.send(:recent_messages_text)
      idx_cliente   = text.index('Cliente:')
      idx_atendente = text.index('Atendente:')
      expect(idx_cliente).to be < idx_atendente
    end

    it 'retorna string vazia quando sem conversation' do
      p = described_class.new('Gere', contact: contact, conversation: nil, stage: nil)
      expect(p.send(:recent_messages_text)).to eq('')
    end

    it 'ignora mensagens com content em branco' do
      create(:message, conversation: conversation, message_type: :incoming, content: nil)
      p = parser('Gere')
      text = p.send(:recent_messages_text)
      lines = text.split("\n").reject(&:blank?)
      lines.each { |l| expect(l).not_to match(/:\s*$/) }
    end
  end
end
