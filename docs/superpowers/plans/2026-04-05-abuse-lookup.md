# --abuse Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `--abuse` flag that finds abuse/spam reporting contacts for VOIP carriers using Claude's web search.

**Architecture:** After the normal carrier lookup, if `--abuse` is set and the carrier type is voip/unknown/other, call the Anthropic API with web search to find the abuse contact. Mobile/landline carriers are skipped with a message. A new `AbuseService` class encapsulates the Anthropic interaction.

**Tech Stack:** Ruby 3.4, `anthropic` gem (official SDK ~> 1.28), Claude Sonnet with `web_search_20250305` tool

---

### Task 1: Add the `anthropic` gem dependency

**Files:**
- Modify: `Gemfile`
- Modify: `callerid.gemspec`

- [ ] **Step 1: Add gem to Gemfile**

Add this line to `Gemfile` after the existing gems:

```ruby
gem "anthropic", "~> 1.28"
```

- [ ] **Step 2: Add gem to gemspec**

Add this line to `callerid.gemspec` inside the spec block, after the existing `add_dependency` lines:

```ruby
spec.add_dependency "anthropic", "~> 1.28"
```

- [ ] **Step 3: Update the Ruby version requirement in gemspec**

The `anthropic` gem requires Ruby >= 3.2.0. Change the `required_ruby_version` line in `callerid.gemspec` from:

```ruby
spec.required_ruby_version = ">= 2.7.0"
```

to:

```ruby
spec.required_ruby_version = ">= 3.2.0"
```

- [ ] **Step 4: Bundle install**

Run: `bundle install`
Expected: Resolves and installs the `anthropic` gem successfully. `Gemfile.lock` is updated.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock callerid.gemspec
git commit -m "feat: add anthropic gem dependency for abuse lookup"
```

---

### Task 2: Create AbuseService

**Files:**
- Create: `lib/callerid/abuse_service.rb`
- Modify: `lib/callerid.rb`

- [ ] **Step 1: Create `lib/callerid/abuse_service.rb`**

```ruby
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
```

- [ ] **Step 2: Add require to `lib/callerid.rb`**

Add this line after the existing requires in `lib/callerid.rb`:

```ruby
require_relative "callerid/abuse_service"
```

The file should look like:

```ruby
# frozen_string_literal: true

require_relative "callerid/version"
require_relative "callerid/lookup_service"
require_relative "callerid/abuse_service"
require_relative "callerid/cli"

module CallerID
  class Error < StandardError; end
end
```

- [ ] **Step 3: Verify it loads**

Run: `ruby -e "require_relative 'lib/callerid'; puts 'OK'"`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add lib/callerid/abuse_service.rb lib/callerid.rb
git commit -m "feat: add AbuseService for carrier abuse contact lookup"
```

---

### Task 3: Wire `--abuse` flag into CLI and display

**Files:**
- Modify: `lib/callerid/cli.rb:10-14` (add option)
- Modify: `lib/callerid/cli.rb:16-35` (lookup method)
- Modify: `lib/callerid/cli.rb:59-113` (display methods)

- [ ] **Step 1: Add the `--abuse` option**

In `lib/callerid/cli.rb`, add this line after the existing `option :debug` line (line 14):

```ruby
option :abuse, aliases: "-a", type: :boolean, desc: "Lookup abuse reporting contact for VOIP carriers"
```

- [ ] **Step 2: Add abuse lookup logic to the `lookup` method**

In `lib/callerid/cli.rb`, replace the `lookup` method (lines 16-35) with:

```ruby
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
      api_key: options[:api_key] ? nil : nil,
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
```

- [ ] **Step 3: Update `display_result` to accept abuse_result**

Replace the `display_result` method with:

```ruby
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
```

- [ ] **Step 4: Add `display_abuse` method**

Add this method inside the `private` section of the CLI class, after `display_table`:

```ruby
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
```

- [ ] **Step 5: Verify the CLI loads and shows help**

Run: `ruby -Ilib bin/callerid help lookup`
Expected: Output includes `--abuse` / `-a` option in the help text.

- [ ] **Step 6: Commit**

```bash
git add lib/callerid/cli.rb
git commit -m "feat: wire --abuse flag into CLI with display logic"
```

---

### Task 4: Integration test with live API

**Files:** None — manual verification only.

- [ ] **Step 1: Test with a VOIP number (abuse lookup runs)**

Run:
```bash
op run --env-file .env --account my.1password.com -- ruby -Ilib bin/callerid lookup 6015500102 --abuse --debug
```

Expected: Normal carrier lookup results, followed by either an abuse contact section or "No abuse contact found" message. Debug output shows the Anthropic API interaction.

- [ ] **Step 2: Test with a known mobile number (abuse lookup skipped)**

Run:
```bash
op run --env-file .env --account my.1password.com -- ruby -Ilib bin/callerid lookup 6015500102 --abuse
```

If the number returns as `mobile` type, you should see:
```
Abuse Lookup: Skipped — [carrier] is a regulated mobile provider
```

- [ ] **Step 3: Test without --abuse flag (no abuse section)**

Run:
```bash
op run --env-file .env --account my.1password.com -- ruby -Ilib bin/callerid lookup 6015500102
```

Expected: Normal output with no abuse section.

- [ ] **Step 4: Test JSON output with --abuse**

Run:
```bash
op run --env-file .env --account my.1password.com -- ruby -Ilib bin/callerid lookup 6015500102 --abuse -f json
```

Expected: JSON output includes an `"abuse"` key.

- [ ] **Step 5: Commit all changes and push**

```bash
git push origin main
```
