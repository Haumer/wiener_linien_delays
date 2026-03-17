module Transit
  class CLI
    COMMANDS = %w[cities status delays line help].freeze

    def initialize(args)
      @args = args
      @client = Client.new
    end

    def run
      command = @args.shift || "help"
      return help unless COMMANDS.include?(command)
      send(command)
    end

    private

    def cities
      data = @client.cities
      return error(data) if data.is_a?(Hash) && data["error"]

      puts "Available cities:\n\n"
      data.each do |c|
        status = c["has_data"] ? "#{c['lines_monitored']} lines" : "no data"
        puts "  %-18s %s" % [c["key"], "#{c['name']} (#{status})"]
      end
      puts "\nUsage: transit status <city>"
    end

    def status
      city = @args.shift || "wien"
      data = @client.line_health(city: city)
      return error(data) if data["error"]

      s = data["summary"]
      puts "#{data['city'].upcase} — #{s['total_lines']} lines"
      puts "  On time: #{s['ok']}  Minor: #{s['minor_delay']}  Major: #{s['major_delay']}  Disrupted: #{s['disrupted']}"
      puts "  Updated: #{data['recorded_at']}"
    end

    def delays
      city = @args.shift || "wien"
      category = @args.shift
      data = @client.line_health(city: city, category: category)
      return error(data) if data["error"]

      delayed = (data["lines"] || []).select { |l| l["status"] != "ok" }
        .sort_by { |l| -(l["max_delay_seconds"] || 0) }

      if delayed.empty?
        puts "#{city}: All lines on time."
        return
      end

      puts "#{city.upcase} — #{delayed.size} delayed lines\n\n"
      puts "  %-10s %-8s %8s %8s  %s" % %w[LINE TYPE AVG MAX STATUS]
      puts "  " + "-" * 50

      delayed.each do |l|
        avg = format_delay(l["avg_delay_seconds"])
        max = format_delay(l["max_delay_seconds"])
        puts "  %-10s %-8s %8s %8s  %s" % [l["line"], l["category"], avg, max, l["status"]]
      end
    end

    def line
      city = @args.shift || "wien"
      line_name = @args.shift
      return puts("Usage: transit line <city> <line>") unless line_name

      data = @client.line_health(city: city)
      return error(data) if data["error"]

      info = (data["lines"] || []).find { |l| l["line"] == line_name }
      return puts("Line #{line_name} not found in #{city}") unless info

      score = reliability_score(info)
      grade = reliability_grade(score)

      puts "#{line_name} (#{info['category']}) — #{city}"
      puts "  Grade: #{grade}  Reliability: #{score}%"
      puts "  Avg delay: #{format_delay(info['avg_delay_seconds'])}  Max: #{format_delay(info['max_delay_seconds'])}"
      puts "  Vehicles: #{info['vehicle_count']}  Stalled: #{info['stalled_count']}"
      puts "  Status: #{info['status']}"
    end

    def help
      puts <<~HELP
        transit — Austrian public transit delay data

        Commands:
          transit cities                 List available cities
          transit status [city]          Network overview (default: wien)
          transit delays [city] [type]   Show delayed lines (type: tram/bus/sbahn/rail)
          transit line <city> <line>     Detail for a specific line

        Environment:
          TRANSIT_API_HOST  API base URL (default: http://localhost:3003)

        Examples:
          transit status wien
          transit delays graz tram
          transit line wien 13A
      HELP
    end

    def error(data)
      $stderr.puts "Error: #{data['error']}"
      exit 1
    end

    def format_delay(seconds)
      return "0m" unless seconds&.positive?
      minutes = (seconds / 60.0).round(1)
      minutes >= 1 ? "+#{minutes.round}m" : "+#{seconds}s"
    end

    def reliability_score(line_info)
      # Approximate from status — proper score needs history endpoint
      case line_info["status"]
      when "ok" then 95
      when "minor_delay" then 75
      when "major_delay" then 50
      when "disrupted" then 25
      else 90
      end
    end

    def reliability_grade(score)
      if score >= 95 then "A"
      elsif score >= 85 then "B"
      elsif score >= 70 then "C"
      elsif score >= 50 then "D"
      else "F"
      end
    end
  end
end
