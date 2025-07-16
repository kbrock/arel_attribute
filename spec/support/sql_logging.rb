log = Logger.new(STDERR)
# log = Logger.new('db.log')
log.level = ENV["SQL"]&.downcase == "true" ? Logger::Severity::DEBUG : Logger::Severity::UNKNOWN
ActiveRecord::Base.logger = log
