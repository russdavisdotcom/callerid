# --abuse Flag: Carrier Abuse Contact Lookup

## Summary

Add an `--abuse` / `-a` flag to the `lookup` command that finds the abuse/spam reporting contact (email or form URL) for VOIP carriers using Claude's web search capability.

## Behavior

1. Normal carrier lookup runs first (Twilio → NumLookupAPI → fallback)
2. If `--abuse` flag is set, check carrier type:
   - **mobile or landline** → skip abuse lookup, display: `"Abuse lookup skipped — [carrier name] is a regulated [type] provider"`
   - **voip, unknown, or other** → call Anthropic API with web search to find abuse contact
3. Display abuse contact info below normal results

## CLI Changes

File: `lib/callerid/cli.rb`

- Add `option :abuse, aliases: "-a", type: :boolean, desc: "Lookup abuse reporting contact for VOIP carriers"`
- After normal lookup, if `--abuse` is set, call `AbuseService` with carrier name and phone number
- Pass result to a new `display_abuse_result` method

## New File: `lib/callerid/abuse_service.rb`

Class `CallerID::AbuseService`:

- Initialize with `api_key` (from env `ANTHROPIC_API_KEY`) and `debug` flag
- `lookup(carrier_name, phone_number)` method:
  - Calls Anthropic API using the `anthropic` Ruby SDK
  - Model: `claude-sonnet-4-20250514`
  - Enables the `web_search` tool
  - Prompt asks Claude to find the abuse/spam reporting email address or form URL for the given VOIP carrier
  - Parses response to extract email and/or URL
  - Returns hash: `{ email: "...", url: "...", raw: "..." }` or `{ error: "..." }`

## Display

Table output adds a new section after carrier info:

When abuse contact is found:
```
Abuse Contact:
  Email: abuse@example-voip.com
  URL:   https://example-voip.com/report-spam
```

When skipped (mobile/landline):
```
Abuse Lookup: Skipped — Verizon Wireless is a regulated mobile provider
```

When abuse lookup fails or finds nothing:
```
Abuse Lookup: No abuse contact found for [carrier name]
```

JSON output includes an `abuse` key with the same data.

## Dependencies

Add to Gemfile and gemspec:
- `anthropic` Ruby SDK gem

## Credentials

- `ANTHROPIC_API_KEY` — already stored in 1Password ("Anthropic API - CallerID") and referenced in `.env`

## Files Changed

- `lib/callerid/cli.rb` — add `--abuse` option, abuse lookup logic, display method
- `lib/callerid/abuse_service.rb` — new file, Anthropic API integration
- `lib/callerid.rb` — require the new service
- `Gemfile` — add `anthropic` gem
- `callerid.gemspec` — add `anthropic` dependency
