class Api::V1::Accounts::Kanban::GamificationController < Api::V1::Accounts::BaseController
  def rankings
    users = Current.account.users.where(account_users: { role: %w[agent administrator] })
    all_account_items = Current.account.kanban_items

    payload = users.map do |user|
      items = all_account_items.where(assignee_id: user.id)
      won   = items.where.not(won_at: nil)
      lost  = items.where.not(lost_at: nil)
      open  = items.where(won_at: nil, lost_at: nil)

      total_value = won.sum(:value).to_f
      closeable   = won.count + lost.count
      conv_rate   = closeable > 0 ? (won.count.to_f / closeable * 100).round(1) : 0.0

      # Points: win = 10pts, total managed = 1pt, conversion > 50% = bonus 5pts
      points = (won.count * 10) + items.count + (conv_rate > 50 ? 5 : 0)

      {
        agent: {
          id: user.id,
          name: user.name,
          avatar_url: user.avatar_url,
          email: user.email,
        },
        stats: {
          total: items.count,
          won: won.count,
          lost: lost.count,
          open: open.count,
          value: total_value,
          conversion_rate: conv_rate,
        },
        points: points,
      }
    end

    # Only include agents who have at least one item, sorted by points
    payload.select! { |a| a[:stats][:total] > 0 || a[:stats][:won] > 0 }
    payload.sort_by! { |a| -a[:points] }

    render json: { payload: payload }
  end

  def overview
    account = Current.account
    now = Time.current
    month_start = now.beginning_of_month
    month_end   = now.end_of_month
    week_start  = now.beginning_of_week
    today_start = now.beginning_of_day

    all_items   = account.kanban_items
    month_won   = all_items.where(won_at: month_start..month_end)
    week_won    = all_items.where(won_at: week_start..now)
    today_won   = all_items.where(won_at: today_start..now)
    month_new   = all_items.where(created_at: month_start..month_end)

    render json: {
      payload: {
        month: {
          won:   month_won.count,
          new:   month_new.count,
          value: month_won.sum(:value).to_f,
        },
        week: {
          won:   week_won.count,
          value: week_won.sum(:value).to_f,
        },
        today: {
          won:   today_won.count,
          value: today_won.sum(:value).to_f,
        },
        total: {
          open: all_items.where(won_at: nil, lost_at: nil).count,
          won:  all_items.where.not(won_at: nil).count,
          lost: all_items.where.not(lost_at: nil).count,
        },
      }
    }
  end

  def recent_wins
    wins = Current.account.kanban_items
      .where.not(won_at: nil)
      .includes(:assignee, :stage, :pipeline)
      .order(won_at: :desc)
      .limit(20)

    render json: {
      payload: wins.map { |item|
        {
          id: item.id,
          title: item.title,
          value: item.value.to_f,
          won_at: item.won_at.to_i,
          pipeline_name: item.pipeline.name,
          stage_name: item.stage.name,
          stage_color: item.stage.color,
          assignee: item.assignee ? { id: item.assignee.id, name: item.assignee.name, avatar_url: item.assignee.avatar_url } : nil,
        }
      }
    }
  end
end
