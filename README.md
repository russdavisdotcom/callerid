# CallerID

A Ruby command-line tool to lookup phone numbers and find out their carrier/provider information.

## Features

- 🔍 Lookup phone numbers and get carrier information
- 📱 Support for mobile and landline numbers
- 🎨 Beautiful colored terminal output
- 📊 Multiple output formats (table, JSON)
- 🔌 Integrates with Twilio Lookup API

## Installation

1. Clone or download this repository
2. Install dependencies:

```bash
bundle install
```

3. Make the executable available (optional):

```bash
# Add to your PATH or create a symlink
ln -s $(pwd)/bin/callerid /usr/local/bin/callerid
```

## Configuration

### Using Twilio Lookup API (Recommended)

The tool uses Twilio's Lookup API to get detailed carrier information. You'll need:

1. A Twilio account (sign up at https://www.twilio.com)
2. Your Account SID and Auth Token from the Twilio Console

You can provide credentials in three ways:

#### Option 1: Environment Variables (Recommended)

**Bash/Zsh:**
```bash
export TWILIO_ACCOUNT_SID="your_account_sid"
export TWILIO_AUTH_TOKEN="your_auth_token"
```

**Fish Shell:**
```fish
set -gx TWILIO_ACCOUNT_SID "your_account_sid"
set -gx TWILIO_AUTH_TOKEN "your_auth_token"
```

To make these persistent in fish shell, add them to your `~/.config/fish/config.fish` file:
```fish
set -Ux TWILIO_ACCOUNT_SID "your_account_sid"
set -Ux TWILIO_AUTH_TOKEN "your_auth_token"
```

#### Option 2: Command Line Options

```bash
./bin/callerid lookup +1234567890 -k YOUR_ACCOUNT_SID -s YOUR_AUTH_TOKEN
```

#### Option 3: Create a `.env` file (requires dotenv gem)

```bash
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
```

## Usage

### Basic Lookup

```bash
./bin/callerid lookup +1234567890
```

Or with the phone number in various formats:

```bash
./bin/callerid lookup "(123) 456-7890"
./bin/callerid lookup 1234567890
./bin/callerid lookup 1-123-456-7890
./bin/callerid "+1 (765) 703-8333"
```

**Note:** When using phone numbers with special characters (parentheses, spaces, dashes), you may need to quote them, especially in fish shell:

```bash
# In fish shell or when using special characters, quote the phone number:
./bin/callerid "+1 (765) 703-8333"
./bin/callerid "(765) 703-8333"
```

### Output Formats

**Table format (default):**
```bash
./bin/callerid lookup +1234567890
```

**JSON format:**
```bash
./bin/callerid lookup +1234567890 -f json
```

### Examples

```bash
# Lookup a US phone number
./bin/callerid lookup +14155551234

# Lookup with JSON output
./bin/callerid lookup +14155551234 --format json

# Lookup with explicit credentials
./bin/callerid lookup +14155551234 -k ACxxxxx -s your_token
```

## Output

The tool displays:
- Phone number (normalized)
- National format
- Country code
- Carrier name
- Carrier type (mobile, landline, voip, etc.)
- Mobile Network Code (MNC)
- Mobile Country Code (MCC)

## Requirements

- Ruby 2.7 or higher
- Bundler

## Dependencies

- `thor` - CLI framework
- `httparty` - HTTP client
- `colorize` - Terminal colors

## Troubleshooting

### "Twilio credentials not configured"

Make sure you've set the `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN` environment variables, or pass them via command-line options.

### "Invalid phone number format"

Ensure the phone number is in a valid format. The tool accepts:
- E.164 format: `+1234567890`
- US format: `(123) 456-7890`
- Plain digits: `1234567890`

### API Rate Limits

Twilio Lookup API has rate limits based on your account type. Free accounts have lower limits. Consider upgrading if you need higher throughput.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

