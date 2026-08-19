# frozen_string_literal: true

require 'rails_helper'

# Sprint v67 — detector de URL que força resposta em texto (em vez de TTS).
RSpec.describe AiAgent::ContentInspector do
  describe '.contains_url?' do
    context 'sem URL (deve responder false)' do
      ['Olá Maria',
       'Tudo certo, qualquer dúvida estou aqui.',
       'Pode ser.',
       'Olá! Conta: 12345-6',
       'Email: maria@example.com',
       'Me mande um e-mail em joao.silva@volponi.adv.br por favor',
       '',
       '   ',
       nil].each do |input|
        it "=> false para #{input.inspect}" do
          expect(described_class.contains_url?(input)).to be(false)
        end
      end
    end

    context 'com URL (deve responder true)' do
      ['Acesse https://example.com',
       'Acesse http://example.com',
       'Veja em www.youtube.com',
       'Instagram: instagram.com/bccprev',
       'Meet: meet.google.com/xxx',
       'Acesse nosso site volponi.com.br'].each do |input|
        it "=> true para #{input.inspect}" do
          expect(described_class.contains_url?(input)).to be(true)
        end
      end
    end

    context 'casos reais de produção (Instagram / Meet / ZapSign)' do
      ['https://www.instagram.com/volponieoliveira/',
       'https://www.instagram.com/bccprev/',
       'https://meet.google.com/abc-defg-hij',
       'https://app.zapsign.com.br/doc/123',
       'Confirmado! Segue o link da reunião: https://meet.google.com/abc-defg-hij'].each do |input|
        it "=> true para #{input.inspect}" do
          expect(described_class.contains_url?(input)).to be(true)
        end
      end
    end

    it 'NÃO confunde e-mail com URL mesmo junto de texto' do
      expect(described_class.contains_url?('Fale com maria@example.com sobre o caso')).to be(false)
    end

    it 'detecta URL mesmo quando há também um e-mail na mensagem' do
      expect(described_class.contains_url?('Email maria@example.com ou acesse www.volponi.com.br')).to be(true)
    end
  end
end
