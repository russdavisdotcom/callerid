# frozen_string_literal: true

require "thor"
require "colorize"
require "json"
require_relative "lookup_service"
require_relative "abuse_service"

module CallerID
  class CLI < Thor
    desc "lookup PHONE_NUMBER", "Lookup information about a phone number"
    option :api_key, aliases: "-k", desc: "Twilio Account SID"
    option :api_secret, aliases: "-s", desc: "Twilio Auth Token"
    option :format, aliases: "-f", enum: %w[table json], default: "table", desc: "Output format"
    option :debug, aliases: "-d", type: :boolean, desc: "Show debug information"
    option :abuse, aliases: "-a", type: :boolean, desc: "Lookup abuse reporting contact for VOIP carriers"

    def lookup(phone_number)
      service = LookupService.new(
        api_key: options[:api_key],
        api_secret: options[:api_secret],
        debug: options[:debug]
      )

      result = service.lookup(phone_number)

      if result[:error]
        puts "❌ Error: #{result[:error]}".colorize(:red)
        if options[:debug] && result[:debug_info]
          puts "\nDebug Info:".colorize(:yellow)
          puts result[:debug_info]
        end
        exit 1
      end

      abuse_result = nil
      if options[:abuse]
        carrier = result[:carrier] || {}
        abuse_service = AbuseService.new(
          debug: options[:debug]
        )
        abuse_result = abuse_service.lookup(
          carrier[:name] || "Unknown",
          carrier[:type] || "unknown",
          result[:phone_number]
        )
      end

      display_result(result, options[:format], abuse_result)
    end

    desc "version", "Show version information"
    def version
      puts "CallerID v#{CallerID::VERSION}"
    end

    # Handle when no command is provided - treat first arg as phone number
    def self.start(given_args = ARGV, config = {})
      # Known commands that should not be treated as phone numbers
      known_commands = ["lookup", "version", "help"]
      
      # If first argument is not a known command and looks like a phone number
      if given_args.any? && !given_args.first.start_with?("-")
        first_arg = given_args.first
        # If it's not a known command and contains digits, treat as lookup
        if !known_commands.include?(first_arg) && first_arg.match?(/\d/)
          given_args.unshift("lookup")
        end
      end
      
      super(given_args, config)
    end

    private

    def display_result(result, format, abuse_result = nil)
      case format
      when "json"
        result[:abuse] = abuse_result if abuse_result
        puts JSON.pretty_generate(result)
      else
        display_table(result)
        display_abuse(abuse_result) if abuse_result
      end
    end

    def display_table(result)
      puts "\n" + "=" * 60
      puts "📞 Phone Number Lookup Results".colorize(:cyan).bold
      puts "=" * 60

      puts "\nPhone Number:".colorize(:yellow) + " #{result[:phone_number]}"
      
      if result[:national_format]
        puts "National Format:".colorize(:yellow) + " #{result[:national_format]}"
      end

      if result[:country_code]
        puts "Country Code:".colorize(:yellow) + " #{result[:country_code]}"
      end

      if result[:carrier]
        puts "\nCarrier Information:".colorize(:green).bold
        carrier = result[:carrier]
        
        if carrier[:name]
          puts "  Name:".colorize(:white) + " #{carrier[:name]}"
        end
        
        if carrier[:type]
          type_color = carrier[:type].downcase == "mobile" ? :green : :blue
          puts "  Type:".colorize(:white) + " #{carrier[:type]}".colorize(type_color)
        end

        if carrier[:mobile_network_code]
          puts "  MNC:".colorize(:white) + " #{carrier[:mobile_network_code]}"
        end

        if carrier[:mobile_country_code]
          puts "  MCC:".colorize(:white) + " #{carrier[:mobile_country_code]}"
        end
      end

      if result[:note]
        puts "\nNote:".colorize(:yellow) + " #{result[:note]}"
      end

      puts "\nSource:".colorize(:magenta) + " #{result[:source] || 'unknown'}"
      puts "=" * 60 + "\n"
    end

    def display_abuse(abuse_result)
      if abuse_result[:skipped]
        puts "\nAbuse Lookup:".colorize(:yellow) + " Skipped — #{abuse_result[:reason]}"
      elsif abuse_result[:error]
        puts "\n❌ Abuse Lookup Error:".colorize(:red) + " #{abuse_result[:error]}"
      elsif abuse_result[:not_found]
        puts "\nAbuse Lookup:".colorize(:yellow) + " No abuse contact found for #{abuse_result[:carrier_name]}"
      else
        puts "\n" + "Abuse Contact:".colorize(:red).bold
        if abuse_result[:email]
          puts "  Email:".colorize(:white) + " #{abuse_result[:email]}"
        end
        if abuse_result[:url]
          puts "  URL:".colorize(:white) + " #{abuse_result[:url]}"
        end
      end
    end
  end
end

