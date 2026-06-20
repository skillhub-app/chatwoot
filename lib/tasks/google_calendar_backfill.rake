namespace :google_calendar do
  desc 'Backfill google_calendar_id em ai_agent_schedules que já têm refresh_token mas estão sem agenda selecionada'
  task backfill_primary: :environment do
    pending = AiAgentSchedule.where.not(google_refresh_token_encrypted: [nil, ''])
                             .where(google_calendar_id: [nil, ''])
    puts "Schedules pendentes: #{pending.count}"

    pending.find_each do |schedule|
      result = AiAgent::GoogleCalendar::PrimaryCalendarSelectorService.new(schedule).call
      if result
        puts "  ✅ schedule #{schedule.id} (#{schedule.ai_agent&.name}): #{result}"
      else
        puts "  ❌ schedule #{schedule.id} (#{schedule.ai_agent&.name}): falhou (ver log)"
      end
    end

    puts 'Backfill concluído.'
  end
end
