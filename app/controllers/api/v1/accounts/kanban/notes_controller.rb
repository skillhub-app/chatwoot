class Api::V1::Accounts::Kanban::NotesController < Api::V1::Accounts::BaseController
  before_action :fetch_item, except: [:external_create]
  before_action :fetch_note, only: [:update, :destroy]

  def index
    @notes = @item.kanban_notes.ordered
  end

  def create
    @note = @item.kanban_notes.new(content: params.require(:content), author: Current.user)
    @note.save!
  end

  def update
    @note.update!(content: params.require(:content))
  end

  def destroy
    @note.destroy!
    head :ok
  end

  def external_create
    item = Current.account.kanban_items.find_by(id: params[:id])
    return render_not_found_error('Kanban item not found') unless item

    content = params[:content]
    return render_could_not_create_error("content can't be blank") if content.blank?

    author_name_raw = params[:author_name].to_s
    if author_name_raw.length > 100
      return render_could_not_create_error('author_name is too long (maximum 100 characters)')
    end

    @note = item.kanban_notes.new(content: content, author: Current.user)
    @note.save!

    author_name = author_name_raw.strip.presence || 'API'
    activity = KanbanActivity.where(kanban_item: item, action_type: 'note_added')
                             .order(created_at: :desc).first
    activity&.update_columns(metadata: activity.metadata.merge(
      'source' => 'api_external',
      'author_name' => author_name
    ))

    render json: {
      id: @note.id,
      kanban_item_id: @note.kanban_item_id,
      content: @note.content,
      author: { id: Current.user.id, name: Current.user.name },
      author_name_external: params[:author_name].present? ? author_name : nil,
      created_at: @note.created_at
    }, status: :created
  end

  private

  def fetch_item
    pipeline = Current.account.kanban_pipelines.find(params[:pipeline_id])
    @item = pipeline.kanban_items.find(params[:item_id])
  end

  def fetch_note
    @note = @item.kanban_notes.find(params[:id])
  end
end
