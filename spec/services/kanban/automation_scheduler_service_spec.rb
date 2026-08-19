# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::AutomationSchedulerService do
  let(:account)  { create(:account) }
  let(:pipeline) { KanbanPipeline.create!(account: account, name: 'P', position: 0, visibility_type: 'all') }
  let(:stage)    { KanbanStage.create!(pipeline: pipeline, name: 'S', position: 0, probability: 0) }
  let(:item)     { KanbanItem.create!(account: account, pipeline: pipeline, stage: stage, title: 'T', position: 0) }
  let(:automation) do
    KanbanAutomation.create!(pipeline: pipeline, trigger_stage: stage, name: 'A', conditions: {})
  end

  def build_action(delay_minutes:, delay_type:)
    KanbanAutomationAction.create!(
      kanban_automation: automation,
      action_type:       'send_whatsapp',
      delay_minutes:     delay_minutes,
      delay_type:        delay_type,
      config:            { message: 'hi', sender_type: 'system' }
    )
  end

  def scheduled_at_for(action)
    build_action(**action)
    freeze = Time.current
    travel_to(freeze) do
      described_class.new(item, stage).perform
    end
    KanbanAutomationExecution.last.scheduled_at
  end

  around { |ex| travel_to(Time.current) { ex.run } }

  describe 'delay_type conversão para minutos' do
    it 'delay_type=minutes, delay_minutes=10 → +10 min' do
      action = build_action(delay_minutes: 10, delay_type: 'minutes')
      described_class.new(item, stage).perform
      expect(KanbanAutomationExecution.last.scheduled_at).to be_within(2.seconds).of(10.minutes.from_now)
    end

    it 'delay_type=hours, delay_minutes=3 → +180 min' do
      action = build_action(delay_minutes: 3, delay_type: 'hours')
      described_class.new(item, stage).perform
      expect(KanbanAutomationExecution.last.scheduled_at).to be_within(2.seconds).of(180.minutes.from_now)
    end

    it 'delay_type=days, delay_minutes=7 → +10080 min' do
      action = build_action(delay_minutes: 7, delay_type: 'days')
      described_class.new(item, stage).perform
      expect(KanbanAutomationExecution.last.scheduled_at).to be_within(2.seconds).of(10_080.minutes.from_now)
    end

    it 'delay_type=business_days, delay_minutes=2 → +2880 min' do
      action = build_action(delay_minutes: 2, delay_type: 'business_days')
      described_class.new(item, stage).perform
      expect(KanbanAutomationExecution.last.scheduled_at).to be_within(2.seconds).of(2880.minutes.from_now)
    end

    it 'delay_type fora do enum (insert direto) → fallback minutes (multiplier=1)' do
      # insere via SQL para contornar a validação do modelo e testar o fetch(..., 1)
      now = Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')
      KanbanAutomationAction.connection.execute(<<~SQL)
        INSERT INTO kanban_automation_actions
          (kanban_automation_id, action_type, delay_minutes, delay_type, active, config, created_at, updated_at)
        VALUES
          (#{automation.id}, 'send_whatsapp', 5, 'unknown_unit', true, '{"message":"hi","sender_type":"system"}', '#{now}', '#{now}')
      SQL
      described_class.new(item, stage).perform
      expect(KanbanAutomationExecution.last.scheduled_at).to be_within(2.seconds).of(5.minutes.from_now)
    end
  end
end
