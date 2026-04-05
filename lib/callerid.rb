# frozen_string_literal: true

require_relative "callerid/version"
require_relative "callerid/lookup_service"
require_relative "callerid/cli"

module CallerID
  class Error < StandardError; end
end

