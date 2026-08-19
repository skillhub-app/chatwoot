# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KanbanItem do
  let(:account)  { create(:account) }
  let(:pipeline) { KanbanPipeline.create!(account: account, name: 'P', position: 0, visibility_type: 'all') }
  let(:stage_a)  { KanbanStage.create!(pipeline: pipeline, name: 'A', position: 0, probability: 0) }
  let(:stage_b)  { KanbanStage.create!(pipeline: pipeline, name: 'B', position: 1, probability: 50) }

  describe 'stage_entered_at' do
    it 'é preenchido com Time.current ao criar um card' do
      freeze_time do
        item = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'T', position: 0)
        expect(item.stage_entered_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'é atualizado quando o card muda de etapa' do
      item = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'T', position: 0)

      travel_to(2.hours.from_now) do
        item.update!(stage: stage_b)
        expect(item.stage_entered_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'NÃO muda ao atualizar outros atributos sem mudar de etapa' do
      item = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'T', position: 0)
      original_entered_at = item.stage_entered_at

      travel_to(1.hour.from_now) do
        item.update!(title: 'Novo título')
        expect(item.reload.stage_entered_at).to be_within(1.second).of(original_entered_at)
      end
    end

    it 'cards mais novos na etapa aparecem primeiro via .ordered' do
      item_old = nil
      item_new = nil

      travel_to(2.hours.ago) do
        item_old = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'Antigo', position: 0)
      end

      travel_to(1.hour.ago) do
        item_new = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'Novo', position: 0)
      end

      ordered_ids = KanbanItem.for_stage(stage_a.id).ordered.pluck(:id)
      expect(ordered_ids.index(item_new.id)).to be < ordered_ids.index(item_old.id)
    end

    it 'cards com stage_entered_at NULL aparecem no final via .ordered' do
      item_with    = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'Com', position: 0)
      item_without = KanbanItem.create!(account: account, pipeline: pipeline, stage: stage_a, title: 'Sem', position: 0)
      # Forçar NULL via update_column (bypass callback)
      item_without.update_column(:stage_entered_at, nil)

      ordered_ids = KanbanItem.for_stage(stage_a.id).ordered.pluck(:id)
      expect(ordered_ids.last).to eq(item_without.id)
    end
  end
end
