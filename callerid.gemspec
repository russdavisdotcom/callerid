# frozen_string_literal: true

require_relative "lib/callerid/version"

Gem::Specification.new do |spec|
  spec.name          = "callerid"
  spec.version       = CallerID::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "A CLI tool to lookup phone numbers and find carrier information"
  spec.description   = "CallerID is a command-line tool that helps you lookup phone numbers and discover their carrier/provider information using the Twilio Lookup API."
  spec.homepage      = "https://github.com/yourusername/callerid"
  spec.license       = "MIT"

  spec.files         = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir        = "bin"
  spec.executables   = ["callerid"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "twilio-ruby", "~> 7.0"
  spec.add_dependency "anthropic", "~> 1.28"
end

