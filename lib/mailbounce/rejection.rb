require "ipaddr"

require "mailbounce/status"

module MailBounce
  # Classifies an SMTP rejection: recipient fault vs sender/exchange.
  class Rejection
    REPLY_CODE = /\A\s*(?<code>[245]\d\d)\b/

    # RFC 3463 §3.2, class dropped. 1.2 is the system; permanently reported it
    # is as dead as a mailbox (transient 4.1.2 is merely unreachable). 1.10
    # (RFC 7505) is a domain's null MX — as lasting a fact as a dead mailbox.
    INVALID_CONDITIONS = %w[ 1.1 1.2 1.3 1.6 1.10 2.1 ].freeze

    FULL_CONDITIONS = %w[ 2.2 ].freeze

    OVERSIZED_CONDITIONS = %w[ 2.3 3.4 ].freeze

    # RFC 3463 §3.2: sender's address, not the recipient's.
    SENDER_CONDITIONS = %w[ 1.7 1.8 ].freeze

    # Network, system, protocol, policy — the exchange, not the mailbox.
    BLOCKED_SUBJECTS = %w[ 3 4 5 7 ].freeze

    # Common MTA wording when no enhanced status is present. No bare
    # "does not exist": that predicate takes any noun, so "sender address does
    # not exist" would read as a dead recipient.
    # No "mailbox unavailable": RFC 5321 §4.2.3 uses that phrase for both 450
    # (busy / temp policy) and 550 (not found / no access / policy).
    INVALID_TEXT = /user unknown|unknown user|no such (?:user|recipient)|recipient not found|invalid recipient/i

    FULL_TEXT = /mailbox full|over quota|quota exceeded|mailbox size limit exceeded|exceeded storage allocation/i

    OVERSIZED_TEXT = /message (?:is )?too large|exceeds the maximum size|message size limit/i

    BLOCKED_TEXT = /blocked|blacklist|spam|denied/i

    QUAD = /(?:\d{1,3}\.){3}\d{1,3}/

    # Mapped form first: otherwise `\h*(?::\h*){2,}` stops at `::ffff:203`.
    ADDRESS = /\h*(?::\h*)+:#{QUAD}|#{QUAD}|\h*(?::\h*){2,}/

    attr_reader :response

    def initialize(response:, sending_ip: nil)
      @response = response.to_s
      @sending_ips = Array(sending_ip).compact
    end

    # Prefer :unknown over a guess — a wrongful retire is worse than extra retries.
    def category
      @category ||=
        if about_us?
          :blocked
        else
          categorized_by_status || categorized_by_text || :unknown
        end
    end

    # What the server claimed (5xx / class 5), not what we made of it.
    def permanent?
      if status
        status.permanent?
      else
        reply_code.to_s.start_with?(Status::PERMANENT_CLASS)
      end
    end

    def about_us?
      ours.any? { |ip| quoted_addresses.include?(ip) }
    end

    def status
      @status ||= Status.parse(@response)
    end

    private
      # Unrecognized conditions fall through so bare 5.0.0 can use the diagnostic text.
      def categorized_by_status
        if status
          case status.condition
          when *INVALID_CONDITIONS then :invalid
          when *FULL_CONDITIONS then :full
          when *OVERSIZED_CONDITIONS then :oversized
          when *SENDER_CONDITIONS then :blocked
          else :blocked if BLOCKED_SUBJECTS.include?(status.subject)
          end
        end
      end

      def categorized_by_text
        case @response
        when INVALID_TEXT then :invalid
        when FULL_TEXT then :full
        when OVERSIZED_TEXT then :oversized
        when BLOCKED_TEXT then :blocked
        end
      end

      def reply_code
        @response[REPLY_CODE, :code]
      end

      def ours
        @ours ||= @sending_ips.filter_map { |ip| address_for(ip) }
      end

      def quoted_addresses
        @quoted_addresses ||= @response.scan(ADDRESS).filter_map { |token| address_for(token) }
      end

      # `.native` so ::ffff:203.0.113.9 and 203.0.113.9 compare equal.
      def address_for(value)
        IPAddr.new(value.to_s).native
      rescue StandardError
        nil
      end
  end
end
