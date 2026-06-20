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

    puts 'Backfill de primary concluído.'

    # Após o backfill, garante as tools nativas em TODO schedule conectado.
    Rake::Task['google_calendar:activate_native_tools'].invoke
  end

  desc 'Cadastra as tools nativas de calendário em todos os schedules google_connected?'
  task activate_native_tools: :environment do
    connected = AiAgentSchedule.where.not(google_calendar_id: [nil, ''])
                               .where.not(google_refresh_token_encrypted: [nil, ''])
    puts "Schedules conectados: #{connected.count}"

    connected.find_each do |schedule|
      agent = schedule.ai_agent
      next unless agent

      tools = AiAgent::NativeToolRegistry.activate(agent, 'google_calendar')
      puts "  ✅ agente #{agent.id} (#{agent.name}): #{tools.size} tools nativas ativas"
    rescue StandardError => e
      puts "  ❌ agente #{schedule.ai_agent_id}: #{e.message}"
    end

    puts 'Ativação de tools nativas concluída.'
  end
end
