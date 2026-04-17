class Api::V1::Accounts::Kanban::ActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_item

  def index
    @activities = @item.kanban_activities.ordered
  end

  private

  def fetch_item
    pipeline = Current.account.kanban_pipelines.find(params[:pipeline_id])
    @item = pipeline.kanban_items.find(params[:item_id])
  end
end
