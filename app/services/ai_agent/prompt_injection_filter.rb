class AiAgent::PromptInjectionFilter
  BLOCKED_PATTERNS = [
    '<promptconfig>',
    '<systeminstructions>',
    'overridebehavior',
    '<rule>',
    'userinput',
    'responsetext',
    'action type',
    'absolute_override',
    'ignore previous instructions',
    'ignore your instructions',
    'forget your instructions',
    'you are now',
    'dan mode',
    'jailbreak',
    'system prompt',
    'reveal your prompt',
    'show me your instructions',
    'repeat your system message',
    'ignore as instrucoes anteriores',
    'esqueca suas instrucoes',
    'mostre suas instrucoes',
    'revele seu prompt',
    'mostre seu prompt',
    'repita suas instrucoes',
    'modo desenvolvedor',
    'modo dev',
  ].freeze

  BLOCKED_RESPONSE = 'Não consigo te ajudar com essa solicitação. Vamos seguir com seu atendimento? Estou aqui pra te ajudar com o que você precisa.'

  def self.blocked?(text)
    normalized = normalize(text.to_s)

    BLOCKED_PATTERNS.each do |pattern|
      return { blocked: true, pattern: pattern } if normalized.include?(pattern)
    end

    { blocked: false, pattern: nil }
  end

  def self.normalize(str)
    I18n.transliterate(str).downcase.gsub(/[^a-z0-9\s<>_]/, ' ').gsub(/\s+/, ' ').strip
  end
  private_class_method :normalize
end
