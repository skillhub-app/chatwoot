require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe AutomationRule do
  describe 'concerns' do
    it_behaves_like 'reauthorizable'
  end

  describe 'associations' do
    let(:account) { create(:account) }
    let(:params) do
      {
        name: 'Notify Conversation Created and mark priority query',
        description: 'Notify all administrator about conversation created and mark priority query',
        event_name: 'conversation_created',
        account_id: account.id,
        conditions: [
          {
            attribute_key: 'browser_language',
            filter_operator: 'equal_to',
            values: ['en'],
            query_operator: 'AND'
          },
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            values: %w[USA UK],
            query_operator: nil
          }
        ],
        actions: [
          {
            action_name: :send_message,
            action_params: ['Welcome to the chatwoot platform.']
          },
          {
            action_name: :assign_team,
            action_params: [1]
          },
          {
            action_name: :remove_assigned_agent
          },
          {
            action_name: :remove_assigned_team
          },
          {
            action_name: :add_label,
            action_params: %w[support priority_customer]
          },
          {
            action_name: :assign_agent,
            action_params: [1]
          }
        ]
      }.with_indifferent_access
    end

    it 'returns valid record' do
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'returns invalid record' do
      params[:conditions][0].delete('query_operator')
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be false
      expect(rule.errors.messages[:conditions]).to eq(['Automation conditions should have query operator.'])
    end

    it 'allows labels as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['bug'],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'validates label condition operators' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'is_present',
          values: [],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'allows private_note as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [true],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end
  end

  describe 'kanban cross-account validation' do
    let(:account)       { create(:account) }
    let(:other_account) { create(:account) }
    let(:pipeline)      { KanbanPipeline.create!(account: account, name: 'P', position: 0, visibility_type: 'all') }
    let(:stage)         { KanbanStage.create!(pipeline: pipeline, name: 'S', position: 0, probability: 0) }
    let(:other_pipeline) { KanbanPipeline.create!(account: other_account, name: 'P2', position: 0, visibility_type: 'all') }
    let(:other_stage)   { KanbanStage.create!(pipeline: other_pipeline, name: 'S2', position: 0, probability: 0) }

    it 'accepts kanban_stage_id condition belonging to same account' do
      rule = build(:automation_rule, account: account,
                                     conditions: [{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                                                    'values' => [stage.id.to_s], 'query_operator' => nil }])
      expect(rule).to be_valid
    end

    it 'rejects kanban_stage_id condition from another account' do
      rule = build(:automation_rule, account: account,
                                     conditions: [{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                                                    'values' => [other_stage.id.to_s], 'query_operator' => nil }])
      expect(rule).not_to be_valid
      expect(rule.errors[:conditions].first).to include('não pertence')
    end

    it 'rejects kanban_stage_id condition with non-existent id' do
      rule = build(:automation_rule, account: account,
                                     conditions: [{ 'attribute_key' => 'kanban_stage_id', 'filter_operator' => 'equal_to',
                                                    'values' => ['999999'], 'query_operator' => nil }])
      expect(rule).not_to be_valid
      expect(rule.errors[:conditions].first).to include('não encontrada')
    end

    it 'accepts move_kanban_stage action with stage from same account' do
      rule = build(:automation_rule, account: account,
                                     actions: [{ 'action_name' => 'move_kanban_stage', 'action_params' => [stage.id] }])
      expect(rule).to be_valid
    end

    it 'rejects move_kanban_stage action with stage from another account' do
      rule = build(:automation_rule, account: account,
                                     actions: [{ 'action_name' => 'move_kanban_stage', 'action_params' => [other_stage.id] }])
      expect(rule).not_to be_valid
    end
  end

  describe 'reauthorizable' do
    context 'when prompt_reauthorization!' do
      it 'marks the rule inactive' do
        rule = create(:automation_rule)
        expect(rule.active).to be true
        rule.prompt_reauthorization!
        expect(rule.active).to be false
      end
    end

    context 'when reauthorization_required?' do
      it 'unsets the error count if conditions are updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(conditions: [{ attribute_key: 'browser_language', filter_operator: 'equal_to', values: ['en'], query_operator: 'AND' }])
        expect(rule.reauthorization_required?).to be false
      end

      it 'will not unset the error count if conditions are not updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(name: 'Updated name')
        expect(rule.reauthorization_required?).to be true
      end
    end
  end
end
