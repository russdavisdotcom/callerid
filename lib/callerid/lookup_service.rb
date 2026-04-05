# frozen_string_literal: true

require "twilio-ruby"
require "httparty"
require "json"
require "colorize"

module CallerID
  class LookupService
    include HTTParty

    def initialize(api_key: nil, api_secret: nil, debug: false)
      @api_key = api_key || ENV["TWILIO_ACCOUNT_SID"]
      @api_secret = api_secret || ENV["TWILIO_AUTH_TOKEN"]
      @debug = debug
    end

    def lookup(phone_number)
      normalized_number = normalize_phone_number(phone_number)
      
      unless normalized_number
        return { error: "Invalid phone number format" }
      end

      # Try Twilio Lookup API first
      result = lookup_twilio(normalized_number)
      
      # If Twilio lookup failed, try alternative
      return lookup_alternative(normalized_number) if result[:error]
      
      # If Twilio succeeded but has no carrier info (error code or null values), try alternative
      if !result[:_has_carrier_info]
        if @debug
          puts "Debug - Twilio returned no carrier info, trying alternative service...".colorize(:yellow)
        end
        
        alt_result = lookup_alternative(normalized_number)
        
        # If alternative found carrier info, merge with Twilio's basic info
        if alt_result[:carrier] && alt_result[:carrier][:name] && alt_result[:carrier][:name] != "Unknown"
          alt_result[:phone_number] = result[:phone_number] if result[:phone_number]
          alt_result[:national_format] = result[:national_format] if result[:national_format]
          alt_result[:country_code] = result[:country_code] if result[:country_code]
          alt_result[:note] = "Carrier info from alternative service (Twilio had no data)"
          return alt_result
        end
      end
      
      # Remove internal flag before returning
      result.delete(:_has_carrier_info)
      result
    end

    private

    def normalize_phone_number(phone_number)
      # Remove all non-digit characters except leading +
      has_plus = phone_number.strip.start_with?("+")
      cleaned = phone_number.gsub(/\D/, "")
      
      # Handle US numbers (10 digits or 11 digits starting with 1)
      if cleaned.length == 10
        "+1#{cleaned}"
      elsif cleaned.length == 11 && cleaned.start_with?("1")
        "+#{cleaned}"
      elsif has_plus && cleaned.length > 10
        "+#{cleaned}"
      elsif cleaned.length > 10
        "+#{cleaned}"
      else
        nil
      end
    end

    def lookup_twilio(phone_number)
      return { error: "Twilio credentials not configured" } unless @api_key && @api_secret

      begin
        # Initialize Twilio client
        client = Twilio::REST::Client.new(@api_key, @api_secret)
        
        # Perform lookup with line_type_intelligence field (v2 API)
        phone_number_obj = client.lookups.v2.phone_numbers(phone_number).fetch(fields: "line_type_intelligence")
        
        # Debug: show raw response if debug mode is on
        if @debug
          puts "Debug - Twilio Phone Number Object (v2):".colorize(:yellow)
          puts "  Phone Number: #{phone_number_obj.phone_number}"
          puts "  Calling Country Code: #{phone_number_obj.calling_country_code}"
          if phone_number_obj.line_type_intelligence
            line_type_hash = phone_number_obj.line_type_intelligence.is_a?(Hash) ? phone_number_obj.line_type_intelligence : phone_number_obj.line_type_intelligence.to_h
            puts "  Line Type Intelligence:"
            puts JSON.pretty_generate(line_type_hash)
          else
            puts "  Line Type Intelligence: nil"
          end
          puts "\n"
        end
        
        # Extract line_type_intelligence data - the gem returns it as a hash-like object
        line_type_intel = phone_number_obj.line_type_intelligence
        line_type_data = if line_type_intel.nil?
          {}
        elsif line_type_intel.respond_to?(:to_h)
          line_type_intel.to_h
        elsif line_type_intel.is_a?(Hash)
          line_type_intel
        else
          # Try to access as object attributes
          {
            "carrier_name" => line_type_intel.respond_to?(:carrier_name) ? line_type_intel.carrier_name : nil,
            "type" => line_type_intel.respond_to?(:type) ? line_type_intel.type : nil,
            "error_code" => line_type_intel.respond_to?(:error_code) ? line_type_intel.error_code : nil,
            "mobile_network_code" => line_type_intel.respond_to?(:mobile_network_code) ? line_type_intel.mobile_network_code : nil,
            "mobile_country_code" => line_type_intel.respond_to?(:mobile_country_code) ? line_type_intel.mobile_country_code : nil
          }
        end
        
        # Check for Twilio error codes in line_type_intelligence object
        line_type_error_code = line_type_data["error_code"] || line_type_data[:error_code]
        
        # Extract carrier info, handling null values
        # Note: v2 API uses "carrier_name" instead of "name"
        carrier_name = line_type_data["carrier_name"] || line_type_data[:carrier_name]
        carrier_type = line_type_data["type"] || line_type_data[:type]
        carrier_mnc = line_type_data["mobile_network_code"] || line_type_data[:mobile_network_code]
        carrier_mcc = line_type_data["mobile_country_code"] || line_type_data[:mobile_country_code]
        
        # Determine if carrier info is actually available
        # Error code means carrier info not available
        has_carrier_info = carrier_name && carrier_type && !line_type_error_code
        
        result = {
          phone_number: phone_number_obj.phone_number,
          carrier: {
            name: carrier_name,
            type: carrier_type,
            mobile_network_code: carrier_mnc,
            mobile_country_code: carrier_mcc
          },
          country_code: phone_number_obj.calling_country_code,
          national_format: phone_number_obj.respond_to?(:national_format) ? phone_number_obj.national_format : nil,
          source: "twilio",
          _has_carrier_info: has_carrier_info  # Internal flag for fallback logic
        }
        
        # If carrier info is completely missing or has error code, mark for fallback
        unless has_carrier_info
          result[:note] = "Carrier information not available from Twilio (error code: #{line_type_error_code || 'N/A'}). Trying alternative service..."
        end
        
        result
      rescue Twilio::REST::RestError => e
        error_response = { error: "Twilio API error: #{e.message}" }
        
        if @debug
          error_response[:debug_info] = "Error code: #{e.code}\nMessage: #{e.message}"
        end
        
        error_response
      rescue StandardError => e
        { error: "API request failed: #{e.message}" }
      end
    end

    def lookup_alternative(phone_number)
      # Try NumLookupAPI (free tier available)
      result = lookup_numlookup(phone_number)
      return result unless result[:error]
      
      # Final fallback
      {
        phone_number: phone_number,
        carrier: {
          name: "Unknown",
          type: "Unknown"
        },
        note: "Carrier information not available. Try configuring Twilio API credentials or NumLookupAPI key for better results.",
        source: "fallback"
      }
    end
    
    def lookup_numlookup(phone_number)
      # NumLookupAPI - free tier: 100 requests/month
      # API key is optional for basic usage
      api_key = ENV["NUMLOOKUP_API_KEY"]
      
      begin
        # Remove + for this API
        clean_number = phone_number.gsub(/^\+/, "")
        
        url = "https://api.numlookupapi.com/v1/validate/#{clean_number}"
        headers = {}
        headers["apikey"] = api_key if api_key
        
        response = self.class.get(
          url,
          headers: headers,
          format: :json
        )
        
        if response.success?
          data = response.parsed_response
          
          if @debug
            puts "Debug - NumLookupAPI Response:".colorize(:yellow)
            puts JSON.pretty_generate(data)
            puts "\n"
          end
          
          # NumLookupAPI response structure
          carrier_info = data["carrier"] || {}
          line_type = data["line_type"] || data["type"]
          
          {
            phone_number: phone_number,
            carrier: {
              name: carrier_info["name"] || data["carrier_name"],
              type: line_type || carrier_info["type"],
              mobile_network_code: carrier_info["mobile_network_code"],
              mobile_country_code: carrier_info["mobile_country_code"]
            },
            country_code: data["country_code"],
            national_format: data["national_format"] || data["local_format"],
            source: "numlookupapi"
          }
        else
          { error: "NumLookupAPI request failed" }
        end
      rescue StandardError => e
        if @debug
          puts "Debug - NumLookupAPI error: #{e.message}".colorize(:red)
        end
        { error: "NumLookupAPI request failed: #{e.message}" }
      end
    end
  end
end

