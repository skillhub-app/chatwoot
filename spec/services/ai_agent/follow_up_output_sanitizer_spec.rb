require 'rails_helper'

# Sprint v66 — Fix A. Garante que nenhum scaffold do prompt vaze para o WhatsApp
# do lead, independente do que o LLM devolva.
RSpec.describe AiAgent::FollowUpOutputSanitizer do
  describe '.call' do
    it 'mantém uma mensagem limpa intacta' do
      clean = 'Oi, Sol! Passando para saber se você viu minha última mensagem.'
      expect(described_class.call(clean)).to eq(clean)
    end

    it 'remove "Sua tarefa: ..." no início e mantém só o texto seguinte' do
      input = "Sua tarefa: gerar o follow-up\n\nOlá, tudo bem com você?"
      expect(described_class.call(input)).to eq('Olá, tudo bem com você?')
    end

    it 'remove a linha "(Aguardando resposta da cliente)"' do
      input = "(Aguardando resposta da cliente)\nOlá, tudo certo?"
      result = described_class.call(input)
      expect(result).not_to match(/aguardando/i)
      expect(result).to include('Olá, tudo certo?')
    end

    it 'remove cabeçalho "## Sua tarefa:"' do
      input = "## Sua tarefa:\nOlá!"
      expect(described_class.call(input)).to eq('Olá!')
    end

    it 'remove separadores "---"' do
      input = "Olá!\n---\nTudo bem?"
      expect(described_class.call(input)).not_to include('---')
    end

    it 'remove cabeçalho "## Exemplo de mensagem:"' do
      input = "## Exemplo de mensagem:\nfoo\nMensagem real"
      result = described_class.call(input)
      expect(result).not_to match(/exemplo de mensagem/i)
      expect(result).to include('Mensagem real')
    end

    it 'remove cabeçalho "## Contexto da conversa"' do
      input = "## Contexto da conversa (últimas 20 mensagens):\nbar\nMensagem real"
      result = described_class.call(input)
      expect(result).not_to match(/contexto da conversa/i)
      expect(result).to include('Mensagem real')
    end

    it 'remove tags XML soltas que o modelo possa ecoar' do
      input = "<instrucao>\nOlá, tudo bem?\n</instrucao>"
      result = described_class.call(input)
      expect(result).not_to include('<instrucao>')
      expect(result).not_to include('</instrucao>')
      expect(result).to include('Olá, tudo bem?')
    end

    it 'remove markdown (*, _, #, `) — WhatsApp não renderiza' do
      input = 'Oi *Sol*, tudo _bem_? veja #isto `aqui`'
      expect(described_class.call(input)).to eq('Oi Sol, tudo bem? veja isto aqui')
    end

    it 'normaliza espaço em branco excessivo' do
      input = "Linha 1\n\n\n\nLinha 2"
      expect(described_class.call(input)).to eq("Linha 1\n\nLinha 2")
    end

    it 'lida com nil sem quebrar' do
      expect(described_class.call(nil)).to eq('')
    end

    # Regressão central: a string EXATA enviada ao lead Sol (conv 676, msg 22291).
    it 'limpa a string de produção da conv 676 deixando só a mensagem' do
      leaked = "(Aguardando resposta da cliente)\n\n---\n*Sua tarefa: gerar o follow-up*\n\n" \
               'Oi, Sol! Está por aí? Conseguiu ver minha última pergunta?'
      expect(described_class.call(leaked)).to eq('Oi, Sol! Está por aí? Conseguiu ver minha última pergunta?')
    end
  end
end
