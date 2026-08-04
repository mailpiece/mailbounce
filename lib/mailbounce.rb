require "mailbounce/version"
require "mailbounce/status"
require "mailbounce/rejection"
require "mailbounce/recipient"
require "mailbounce/report"

# Reads delivery failures: bounce reports (RFC 3464) and SMTP rejections.
# Reports what a failure is; retiring or retrying is the caller's decision.
module MailBounce
  def self.classify(response:, sending_ip: nil)
    Rejection.new(response: response, sending_ip: sending_ip)
  end

  def self.parse(raw, max_size: Report::MAX_SIZE)
    Report.parse(raw, max_size: max_size)
  end
end
