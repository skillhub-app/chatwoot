# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AutomationRules::KanbanConditionsService do
  let(:account)      { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:pipeline)     { KanbanPipeline.create!(account: account, name: 'Test', position: 0, visibility_type: 'all') }
  let(:stage)        { KanbanStage.create!(pipeline: pipeline, name: 'Stage A', position: 0, probability: 0) }
  let(:other_stage)  { KanbanStage.create!(pipeline: pipeline, name: 'Stage B', position: 1, probability: 0) }
  let(:item) do
    KanbanItem.create!(account: account, pipeline: pipeline, stage: stage,
                       title: 'Test Card', position: 0, conversation: conversation)
  end

  def build_rule(conditions)
    build(:automation_rule, account: account, conditions: conditions)
  end

  describe '.has_kanban_conditions?' do
    it 'returns true when rule has kanban_stage_id condition' do
      rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                           'values' => [stage.id.to_s], 'query_operator' => nil }])
      expect(described_class.has_kanban_conditions?(rule)).to be true
    end

    it 'returns true when rule has kanban_pipeline_id condition' do
      rule = build_rule([{ 'attribute_key' => 'kanban_pipeline_id', 'filter_operator' => 'equal_to',
                           'values' => [pipeline.id.to_s], 'query_operator' => nil }])
      expect(described_class.has_kanban_conditions?(rule)).to be true
    end

    it 'returns false when rule has no kanban conditions' do
      rule = build_rule([{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                           'values' => ['open'], 'query_operator' => nil }])
      expect(described_class.has_kanban_conditions?(rule)).to be false
    end
  end

  describe '#perform' do
    context 'when no kanban conditions in rule' do
      it 'returns true immediately' do
        rule = build_rule([{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                             'values' => ['open'], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be true
      end
    end

    context 'when conversation has no kanban item' do
      it 'returns false and logs debug' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                             'values' => [stage.id.to_s], 'query_operator' => nil }])
        other_conversation = create(:conversation, account: account)
        expect(described_class.new(rule, other_conversation).perform).to be false
      end
    end

    context 'kanban_stage_id condition' do
      before { item }

      it 'returns true when stage matches with equal_to' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                             'values' => [stage.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be true
      end

      it 'returns false when stage does not match with equal_to' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                             'values' => [other_stage.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be false
      end

      it 'returns true when stage differs with not_equal_to' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'not_equal_to',
                             'values' => [other_stage.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be true
      end

      it 'returns false when stage matches with not_equal_to' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'not_equal_to',
                             'values' => [stage.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be false
      end
    end

    context 'kanban_pipeline_id condition' do
      before { item }

      it 'returns true when pipeline matches' do
        rule = build_rule([{ 'attribute_key' => 'kanban_pipeline_id', 'filter_operator' => 'equal_to',
                             'values' => [pipeline.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be true
      end

      it 'returns false when pipeline does not match' do
        other_pipeline = KanbanPipeline.create!(account: account, name: 'Other', position: 1, visibility_type: 'all')
        rule = build_rule([{ 'attribute_key' => 'kanban_pipeline_id', 'filter_operator' => 'equal_to',
                             'values' => [other_pipeline.id.to_s], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be false
      end
    end

    context 'unknown operator' do
      before { item }

      it 'returns true (permissive fallback)' do
        rule = build_rule([{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'contains',
                             'values' => ['999'], 'query_operator' => nil }])
        expect(described_class.new(rule, conversation).perform).to be true
      end
    end
  end
end
