class Api::V1::Accounts::Kanban::ItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:index, :show, :create, :update, :destroy, :move, :won, :lost, :reopen]
  before_action :fetch_item, only: [:show, :update, :destroy, :move, :won, :lost, :reopen]

  def index
    @items = pipeline_items.ordered
    @items = @items.for_stage(params[:stage_id]) if params[:stage_id].present?
    @items = @items.assigned_to(params[:assignee_id]) if params[:assignee_id].present?
    @items = @items.with_source(params[:source]) if params[:source].present?
    @items = @items.with_temperature(params[:temperature]) if params[:temperature].present?
    @items = @items.where('LOWER(title) LIKE ? OR contact_phone LIKE ?',
                          "%#{params[:search].downcase}%", "%#{params[:search]}%") if params[:search].present?
    @items = @items.where('created_at >= ?', params[:created_from]) if params[:created_from].present?
    @items = @items.where('created_at <= ?', params[:created_to]) if params[:created_to].present?
    @items = @items.where('expected_close_date >= ?', params[:close_date_from]) if params[:close_date_from].present?
    @items = @items.where('expected_close_date <= ?', params[:close_date_to]) if params[:close_date_to].present?
    @items = @items.where('value >= ?', params[:value_min]) if params[:value_min].present?
    @items = @items.where('value <= ?', params[:value_max]) if params[:value_max].present?
    if params[:status].present?
      @items = case params[:status]
               when 'won' then @items.won
               when 'lost' then @items.lost
               when 'open' then @items.open
               else @items
               end
    end
  end

  def show; end

  def create
    @item = pipeline_items.new(item_params)
    @item.save!
  end

  def update
    prev_stage_id    = @item.stage_id
    prev_assignee_id = @item.assignee_id
    prev_value       = @item.value

    @item.update!(item_params)

    if @item.stage_id != prev_stage_id
      auto_update_won_lost(@item.stage)
      log_activity('moved', from_stage: prev_stage_id, to_stage: @item.stage_id)
    end
    log_activity('assigned', assignee_id: @item.assignee_id) if @item.assignee_id != prev_assignee_id
    log_activity('value_changed', from: prev_value, to: @item.value) if @item.value != prev_value
  end

  def destroy
    @item.destroy!
    head :ok
  end

  def move
    prev_stage_id = @item.stage_id
    stage = @pipeline.kanban_stages.find(params.require(:stage_id))
    @item.update!(stage: stage, position: params[:position] || @item.position)
    auto_update_won_lost(stage) if prev_stage_id != stage.id
    log_activity('moved', from_stage: prev_stage_id, to_stage: stage.id) if prev_stage_id != stage.id
  end

  def won
    already_won  = @item.won_at.present?
    won_stage    = @pipeline.kanban_stages.find_by(is_won: true)
    prev_stage_id = @item.stage_id

    attrs = { won_at: Time.current, lost_at: nil }
    attrs[:stage_id] = won_stage.id if won_stage && @item.stage_id != won_stage.id

    @item.update!(attrs)
    log_activity('won') unless already_won
    log_activity('moved', from_stage: prev_stage_id, to_stage: won_stage.id) if won_stage && prev_stage_id != won_stage.id
  end

  def lost
    already_lost  = @item.lost_at.present?
    lost_stage    = @pipeline.kanban_stages.find_by(is_lost: true)
    prev_stage_id = @item.stage_id

    attrs = { lost_at: Time.current, won_at: nil }
    attrs[:stage_id] = lost_stage.id if lost_stage && @item.stage_id != lost_stage.id

    @item.update!(attrs)
    log_activity('lost') unless already_lost
    log_activity('moved', from_stage: prev_stage_id, to_stage: lost_stage.id) if lost_stage && prev_stage_id != lost_stage.id
  end

  def reopen
    @item.update!(won_at: nil, lost_at: nil)
    log_activity('reopened')
  end

  private

  def auto_update_won_lost(stage)
    if stage.is_won?
      @item.update_columns(won_at: Time.current, lost_at: nil)
      log_activity('won')
    elsif stage.is_lost?
      @item.update_columns(lost_at: Time.current, won_at: nil)
      log_activity('lost')
    end
  end

  def fetch_pipeline
    @pipeline = Current.account.kanban_pipelines.find(params[:pipeline_id])
  end

  def fetch_item
    @item = pipeline_items.find(params[:id])
  end

  def pipeline_items
    Current.account.kanban_items.for_pipeline(@pipeline.id)
  end

  def item_params
    params.permit(
      :stage_id, :conversation_id, :contact_phone, :title, :value,
      :assignee_id, :position, :source, :temperature, :probability,
      :expected_close_date, :score,
      tags: []
    )
  end

  def log_activity(action_type, metadata = {})
    @item.kanban_activities.create!(
      author_id: Current.user&.id,
      action_type: action_type,
      metadata: metadata
    )
  end
end
