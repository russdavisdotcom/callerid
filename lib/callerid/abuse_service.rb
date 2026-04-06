# frozen_string_literal: true

require "anthropic"
require "json"

module CallerID
  class AbuseService
    SKIP_TYPES = %w[mobile landline].freeze

    def initialize(api_key: nil, debug: false)
      @api_key = api_key || ENV["ANTHROPIC_API_KEY"]
      @debug = debug
    end

    def lookup(carrier_name, carrier_type, phone_number)
      normalized_type = (carrier_type || "").downcase

      if SKIP_TYPES.include?(normalized_type)
        return {
          skipped: true,
          reason: "#{carrier_name} is a regulated #{normalized_type} provider"
        }
      end

      return { error: "Anthropic API key not configured" } unless @api_key

      search_for_abuse_contact(carrier_name, phone_number)
    end

    private

    def search_for_abuse_contact(carrier_name, phone_number)
      client = Anthropic::Client.new(api_key: @api_key)

      message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 1024,
        tools: [
          {
            name: "web_search",
            type: "web_search_20250305"
          }
        ],
        messages: [
          {
            role: :user,
            content: build_prompt(carrier_name, phone_number)
          }
        ]
      )

      if @debug
        puts "Debug - Anthropic response:".colorize(:yellow)
        message.content.each do |block|
          case block
          when Anthropic::ServerToolUseBlock
            puts "  Tool use: #{block.input}"
          when Anthropic::WebSearchToolResultBlock
            puts "  Search result block"
          when Anthropic::TextBlock
            puts "  Text: #{block.text}"
          end
        end
        puts ""
      end

      parse_response(message, carrier_name)
    rescue Anthropic::Errors::RateLimitError
      { error: "Anthropic API rate limit exceeded" }
    rescue Anthropic::Errors::APIStatusError => e
      { error: "Anthropic API error: #{e.message}" }
    rescue StandardError => e
      { error: "Abuse lookup failed: #{e.message}" }
    end

    def build_prompt(carrier_name, phone_number)
      <<~PROMPT
        I need to report an abusive/spam phone call from #{phone_number}, which is a VOIP number from the carrier "#{carrier_name}".

        Search the web to find the abuse or spam reporting contact for this carrier. I need:
        1. An abuse reporting email address (if available)
        2. A URL to an abuse reporting form or page (if available)

        Respond in this exact format and nothing else:
        EMAIL: <email or "none">
        URL: <url or "none">
      PROMPT
    end

    def parse_response(message, carrier_name)
      text = message.content
        .select { |block| block.is_a?(Anthropic::TextBlock) }
        .map(&:text)
        .join("\n")

      email = text.match(/EMAIL:\s*(.+)/)&.captures&.first&.strip
      url = text.match(/URL:\s*(.+)/)&.captures&.first&.strip

      email = nil if email.nil? || email.downcase == "none" || email.empty?
      url = nil if url.nil? || url.downcase == "none" || url.empty?

      if email || url
        { email: email, url: url }
      else
        { not_found: true, carrier_name: carrier_name, raw: text }
      end
    end
  end
end
