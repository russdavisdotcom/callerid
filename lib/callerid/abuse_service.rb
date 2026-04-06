# frozen_string_literal: true

require "anthropic"
require "json"
require "uri"
require "fileutils"

module CallerID
  class AbuseService
    SKIP_TYPES = %w[mobile landline].freeze

    SEARCH_MODEL = "claude-haiku-4-5-20251001"
    DRAFT_MODEL = "claude-haiku-4-5-20251001"

    # Haiku pricing per token
    HAIKU_INPUT_COST_PER_TOKEN = 0.80 / 1_000_000
    HAIKU_OUTPUT_COST_PER_TOKEN = 4.0 / 1_000_000

    CACHE_DIR = File.join(Dir.home, ".callerid", "cache")

    def initialize(api_key: nil, debug: false)
      @api_key = api_key || ENV["ANTHROPIC_API_KEY"]
      @debug = debug
      @total_usage = { input_tokens: 0, output_tokens: 0 }
    end

    attr_reader :total_usage

    def lookup(carrier_name, carrier_type, phone_number)
      normalized_type = (carrier_type || "").downcase

      if SKIP_TYPES.include?(normalized_type)
        return {
          skipped: true,
          reason: "#{carrier_name} is a regulated #{normalized_type} provider"
        }
      end

      return { error: "Anthropic API key not configured" } unless @api_key

      cached = read_cache(carrier_name)
      if cached
        puts "Cache hit for #{carrier_name}".colorize(:green) if @debug
        return cached
      end

      result = search_for_abuse_contact(carrier_name, phone_number)
      write_cache(carrier_name, result) unless result[:error]
      result
    end

    def draft_report(carrier_name, phone_number, abuse_email)
      return { error: "Anthropic API key not configured" } unless @api_key

      client = Anthropic::Client.new(api_key: @api_key)

      message = client.messages.create(
        model: DRAFT_MODEL,
        max_tokens: 512,
        messages: [
          {
            role: :user,
            content: <<~PROMPT
              Draft a brief, professional abuse report email about phone number #{phone_number} from carrier "#{carrier_name}".

              The email should:
              - State that the number is being used for spam/abusive calls
              - Request the carrier investigate and take action
              - Be 3-5 sentences max
              - Be professional and factual

              Return ONLY the email body text, no subject line or greeting.
            PROMPT
          }
        ]
      )

      track_usage(message)

      text = message.content
        .select { |block| block.is_a?(Anthropic::TextBlock) }
        .map(&:text)
        .join("\n")

      { body: text, to: abuse_email, subject: "Abuse Report: #{phone_number}" }
    rescue StandardError => e
      { error: "Draft failed: #{e.message}" }
    end

    def estimated_cost
      input_cost = @total_usage[:input_tokens] * HAIKU_INPUT_COST_PER_TOKEN
      output_cost = @total_usage[:output_tokens] * HAIKU_OUTPUT_COST_PER_TOKEN
      {
        input_tokens: @total_usage[:input_tokens],
        output_tokens: @total_usage[:output_tokens],
        total_cost: (input_cost + output_cost).round(6)
      }
    end

    private

    def cache_key(carrier_name)
      carrier_name.gsub(/[^a-zA-Z0-9_-]/, "_").downcase
    end

    def read_cache(carrier_name)
      path = File.join(CACHE_DIR, "#{cache_key(carrier_name)}.json")
      return nil unless File.exist?(path)

      data = JSON.parse(File.read(path), symbolize_names: true)

      # Expire after 30 days
      cached_at = Time.parse(data.delete(:cached_at).to_s) rescue nil
      return nil if cached_at.nil? || (Time.now - cached_at) > 30 * 24 * 3600

      data
    rescue StandardError
      nil
    end

    def write_cache(carrier_name, result)
      FileUtils.mkdir_p(CACHE_DIR)
      path = File.join(CACHE_DIR, "#{cache_key(carrier_name)}.json")
      data = result.merge(cached_at: Time.now.iso8601)
      File.write(path, JSON.pretty_generate(data))
    rescue StandardError => e
      puts "Warning: could not write cache: #{e.message}".colorize(:yellow) if @debug
    end

    def track_usage(message)
      @total_usage[:input_tokens] += message.usage.input_tokens
      @total_usage[:output_tokens] += message.usage.output_tokens
    end

    def search_for_abuse_contact(carrier_name, phone_number)
      client = Anthropic::Client.new(api_key: @api_key)

      message = client.messages.create(
        model: SEARCH_MODEL,
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

      track_usage(message)

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
