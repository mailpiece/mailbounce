require "mailbounce/status"

module MailBounce
  # One per-recipient block of a delivery status report (RFC 3464 §2.3).
  class Recipient
    FAILED_ACTION = "failed".freeze

    attr_reader :final_recipient, :original_recipient, :action, :diagnostic_code, :remote_mta

    def initialize(final_recipient: nil, original_recipient: nil, failed_recipient: nil,
                   action: nil, status: nil, diagnostic_code: nil, remote_mta: nil)
      @final_recipient = final_recipient
      @original_recipient = original_recipient
      @failed_recipient = failed_recipient
      @action = action
      @status = status
      @diagnostic_code = diagnostic_code
      @remote_mta = remote_mta
    end

    WRAPPED = /\A["'<]|[">']\z/

    # RFC 3464 §2.3.2 wants Final-Recipient; also try Original-Recipient and
    # X-Failed-Recipients so an address-less block is not treated as anonymous
    # (anonymous answers every name).
    def address
      @address ||= sources.filter_map { |source| addressed(source) }.first.to_s
    end

    def anonymous?
      address.empty?
    end

    def failed?
      action.to_s.strip.casecmp?(FAILED_ACTION)
    end

    def permanent?
      status&.permanent? || false
    end

    def permanent_failure?
      failed? && permanent?
    end

    def status
      @parsed_status ||= Status.parse(@status)
    end

    def addressed_to?(recipient)
      named = recipient.to_s.strip

      !named.empty? && named?(named)
    end

    private
      def sources
        [ @final_recipient, @original_recipient, @failed_recipient ]
      end

      # Type-tagged as `rfc822; someone@example.com`.
      def addressed(source)
        address = unwrapped(source.to_s.split(";", 2).last.to_s)

        address unless address.empty?
      end

      # Strip outer brackets/quotes only. Quoted local-parts lose their quotes
      # (safe miss — DSNs rarely carry that form).
      def unwrapped(value)
        address = value.strip

        while address.match?(WRAPPED)
          address = address.sub(/\A["'<]/, "").sub(/[">']\z/, "").strip
        end

        address
      end

      # An RFC 6533 address carries raw UTF-8, but the message it arrived in
      # reads as bytes — the two only compare once their encodings agree.
      def named?(named)
        mine, theirs = comparable(address), comparable(named)

        if mine.encoding == theirs.encoding
          mine.casecmp?(theirs)
        else
          mine.b.casecmp?(theirs.b)
        end
      end

      def comparable(value)
        utf8 = value.dup.force_encoding(Encoding::UTF_8)

        if utf8.valid_encoding?
          utf8
        else
          value.b
        end
      end
  end
end
