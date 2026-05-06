require 'rails_helper'

RSpec.describe AiAgent::ToolExecutor do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  # Minimal tool double — avoids DB for pure render_template unit tests
  def build_tool(template: nil, response_template: nil, name: 'test_tool')
    instance_double(
      AiAgent::Tool,
      name: name,
      ai_agent: ai_agent,
      http_method: 'POST',
      endpoint_url: 'https://example.com/webhook',
      headers: {},
      request_body_template: template,
      response_template: response_template,
      timeout_seconds: 5
    )
  end

  # Access the private render_template via send
  def render(executor, template, vars)
    executor.send(:render_template, template, vars)
  end

  describe '#render_template (private)' do
    let(:tool)     { build_tool }
    let(:executor) { described_class.new(tool, {}) }

    # a) {{var}} sem espaço
    it 'substitutes {{var}} without spaces' do
      expect(render(executor, '{{nome}}', 'nome' => 'Maria')).to eq('Maria')
    end

    # b) {{ var }} com espaço
    it 'substitutes {{ var }} with spaces' do
      expect(render(executor, '{{ nome }}', 'nome' => 'Maria')).to eq('Maria')
    end

    # c) {{  var  }} múltiplos espaços
    it 'substitutes {{  var  }} with multiple spaces' do
      expect(render(executor, '{{  nome  }}', 'nome' => 'Maria')).to eq('Maria')
    end

    # d) Param ausente → "" e warning
    it 'replaces missing placeholder with empty string' do
      expect(render(executor, '{{ausente}}', {})).to eq('')
    end

    it 'logs a warning for missing placeholder' do
      expect(Rails.logger).to receive(:warn).with(/placeholder sem valor.*ausente/)
      render(executor, '{{ausente}}', {})
    end

    # e) Valor numérico → string "30"
    it 'converts numeric values to string' do
      expect(render(executor, '{{idade}}', 'idade' => 30)).to eq('30')
    end

    # f) Booleano → "true"
    it 'converts boolean true to string' do
      expect(render(executor, '{{ativo}}', 'ativo' => true)).to eq('true')
    end

    it 'converts boolean false to string' do
      expect(render(executor, '{{ativo}}', 'ativo' => false)).to eq('false')
    end

    # g) nil → ""
    it 'converts nil value to empty string without logging "nil"' do
      result = render(executor, '{{campo}}', 'campo' => nil)
      expect(result).to eq('')
      expect(result).not_to include('nil')
    end

    # h) Chave com caractere especial (Regexp.escape)
    it 'handles keys that contain regex special chars (dot in key name)' do
      # key with literal dot in name (not dot-notation)
      expect(render(executor, '{{preco}}', 'preco' => '10.00')).to eq('10.00')
    end

    # i) Dot notation: {{ a.b }}
    it 'resolves dot notation placeholders' do
      vars = { 'a' => { 'b' => 'valor' } }
      expect(render(executor, '{{ a.b }}', vars)).to eq('valor')
    end

    it 'resolves triple-level dot notation' do
      vars = { 'user' => { 'address' => { 'city' => 'Campinas' } } }
      expect(render(executor, '{{user.address.city}}', vars)).to eq('Campinas')
    end

    # j) Dot notation com path quebrado → "" e warning
    it 'returns empty string for broken dot-notation path' do
      vars = { 'a' => 'flat_string' }
      expect(render(executor, '{{a.b}}', vars)).to eq('')
    end

    it 'logs warning for broken dot-notation path' do
      vars = { 'a' => 'flat_string' }
      expect(Rails.logger).to receive(:warn).with(/placeholder sem valor.*a\.b/)
      render(executor, '{{a.b}}', vars)
    end

    # Multiple replacements in one template
    it 'replaces all occurrences in a JSON template string' do
      tmpl = '{"a": "{{nome}}", "b": "{{idade}}"}'
      vars = { 'nome' => 'Maria', 'idade' => 30 }
      expect(render(executor, tmpl, vars)).to eq('{"a": "Maria", "b": "30"}')
    end
  end

  describe '#build_body (private)' do
    let(:executor) { described_class.new(tool, params) }

    context 'when template is blank' do
      let(:tool)   { build_tool(template: nil) }
      let(:params) { { 'nome' => 'Maria' } }

      it 'returns params merged with _context' do
        body = executor.send(:build_body)
        expect(body['nome']).to eq('Maria')
        expect(body).to have_key('_context')
      end
    end

    context 'when template is present and valid' do
      let(:tool)   { build_tool(template: '{"nome": "{{nome}}", "idade": {{idade}}}') }
      let(:params) { { 'nome' => 'Maria', 'idade' => 30 } }

      it 'returns parsed JSON with substituted values' do
        body = executor.send(:build_body)
        expect(body['nome']).to eq('Maria')
        expect(body['idade']).to eq(30)
      end
    end

    context 'when template has placeholder without value' do
      let(:tool)   { build_tool(template: '{"nome": "{{nome}}", "cpf": "{{cpf}}"}') }
      let(:params) { { 'nome' => 'Maria' } }

      it 'substitutes missing placeholder with empty string keeping valid JSON' do
        body = executor.send(:build_body)
        expect(body['cpf']).to eq('')
      end
    end

    context 'when template is invalid JSON after substitution' do
      let(:tool)   { build_tool(template: 'not json {{nome}}') }
      let(:params) { { 'nome' => 'Maria' } }

      it 'falls back to raw params + _context and logs error' do
        expect(Rails.logger).to receive(:error).with(/JSON inválido/)
        body = executor.send(:build_body)
        expect(body['nome']).to eq('Maria')
        expect(body).to have_key('_context')
      end
    end
  end

  describe 'smoke test — Volponi payload (18 fields)' do
    let(:template) do
      <<~JSON.strip
        {
          "nome_completo": "{{nome_completo}}",
          "nacionalidade": "{{nacionalidade}}",
          "profissao": "{{profissao}}",
          "estado_civil": "{{estado_civil}}",
          "rg": "{{rg}}",
          "cpf": "{{cpf}}",
          "email": "{{email}}",
          "telefone": "{{telefone}}",
          "sexo": "{{sexo}}",
          "endereco_rua": "{{endereco_rua}}",
          "endereco_bairro": "{{endereco_bairro}}",
          "endereco_cidade": "{{endereco_cidade}}",
          "endereco_estado": "{{endereco_estado}}",
          "endereco_cep": "{{endereco_cep}}",
          "servico_indicado": "{{servico_indicado}}",
          "codigo_contrato": "{{codigo_contrato}}",
          "responsavel_nome_completo": "{{responsavel_nome_completo}}",
          "responsavel_cpf": "{{responsavel_cpf}}"
        }
      JSON
    end

    let(:llm_params) do
      {
        'nome_completo'             => 'João da Silva',
        'nacionalidade'             => 'brasileiro',
        'profissao'                 => 'pedreiro',
        'estado_civil'              => 'casado',
        'rg'                        => '12.345.678-9',
        'cpf'                       => '123.456.789-00',
        'email'                     => 'joao@email.com',
        'telefone'                  => '(19) 99999-1234',
        'sexo'                      => 'masculino',
        'endereco_rua'              => 'Rua das Flores, 100',
        'endereco_bairro'           => 'Centro',
        'endereco_cidade'           => 'Santa Bárbara d\'Oeste',
        'endereco_estado'           => 'SP',
        'endereco_cep'              => '13450-000',
        'servico_indicado'          => 'Aposentadoria',
        'codigo_contrato'           => '3c22e672-fae7-4232-8b18-4a7973541d40',
        'responsavel_nome_completo' => '',
        'responsavel_cpf'           => '',
      }
    end

    let(:tool)     { build_tool(template: template) }
    let(:executor) { described_class.new(tool, llm_params) }

    it 'renders all 18 fields with correct values' do
      body = executor.send(:build_body)
      llm_params.each do |key, expected|
        expect(body[key]).to eq(expected), "Expected body['#{key}'] to eq #{expected.inspect}, got #{body[key].inspect}"
      end
    end

    it 'produces valid JSON (no leftover placeholders)' do
      body = executor.send(:build_body)
      expect(body).to be_a(Hash)
      body.each_value do |v|
        expect(v.to_s).not_to match(/\{\{.*\}\}/)
      end
    end
  end
end
