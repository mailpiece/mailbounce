require "mail"
require "set"

require "mailbounce/recipient"

module MailBounce
  # Machine-readable half of a bounce (RFC 3464). Unreadable input reports nothing.
  class Report
    # RFC 6533 adds the global type for internationalized addresses.
    DELIVERY_STATUS_TYPES = %w[ message/delivery-status message/global-delivery-status ].freeze

    # RFC 3464 §2.1.
    BLANK_LINE = /\r?\n[ \t]*\r?\n/

    FIELD_NAME = /\A(?<name>[A-Za-z][A-Za-z0-9\-]*)[ \t]*:/

    # A bounce is a notice, not a mailbox — Postfix caps its own at 50 KB.
    # Anything past this is not a report anyone meant to send.
    MAX_SIZE = 1024 * 1024

    # Value stays on its line so an empty field cannot swallow the next.
    FIELDS = {
      action: /^Action[ \t]*:[ \t]*(?<value>.+)$/i,
      status: /^Status[ \t]*:[ \t]*(?<value>.+)$/i,
      final_recipient: /^Final-Recipient[ \t]*:[ \t]*(?<value>.+)$/i,
      original_recipient: /^Original-Recipient[ \t]*:[ \t]*(?<value>.+)$/i,
      diagnostic_code: /^Diagnostic-Code[ \t]*:[ \t]*(?<value>.+)$/i,
      remote_mta: /^Remote-MTA[ \t]*:[ \t]*(?<value>.+)$/i
    }.freeze

    def self.parse(raw, max_size: MAX_SIZE)
      new(raw, max_size: max_size)
    end

    def initialize(raw, max_size: MAX_SIZE)
      report = raw.to_s

      @mail = Mail.new(report) if report.bytesize <= max_size
    rescue StandardError
      @mail = nil
    end

    def recipients
      @recipients ||= reported_blocks.map { |block| recipient_from(block) }
    end

    # One unnamed recipient may stand in for any address; a named report only
    # for the address it names.
    def for(address = nil)
      if named = recipients.find { |recipient| recipient.addressed_to?(address) }
        named
      else
        sole_recipient_for(address)
      end
    end

    def any?
      recipients.any?
    end

    private
      def sole_recipient_for(address)
        if recipients.one? && (recipients.first.anonymous? || address.to_s.strip.empty?)
          recipients.first
        end
      end

      def blocks
        delivery_status.to_s.split(BLANK_LINE).flat_map { |chunk| per_recipient(chunk) }
      end

      # Per-recipient blocks carry Action; the report preamble does not.
      def reported_blocks
        @reported_blocks ||= blocks.select { |block| unfolded(block).match?(FIELDS[:action]) }
      end

      # X-Failed-Recipients only when one block and one address — no positional guess.
      def attributable_address
        failed_recipients.first if reported_blocks.one? && failed_recipients.one?
      end

      def failed_recipients
        @failed_recipients ||= failed_recipient_headers.flat_map { |header| header.split(",") }.map(&:strip).reject(&:empty?)
      end

      def failed_recipient_headers
        Array(@mail&.[]("X-Failed-Recipients")).map(&:to_s)
      rescue StandardError
        []
      end

      # A block ends when a field it already has reappears (order is not fixed).
      # The names are kept rather than matched for again: a block grows, and
      # reading all of it per line costs the square of its length.
      def per_recipient(chunk)
        blocks, named = [], Set.new

        chunk.lines.each do |line|
          name = field_name(line)

          if blocks.empty? || named.include?(name)
            blocks << +line
            named = Set.new
          else
            blocks.last << line
          end

          named << name if name
        end

        blocks
      end

      # Field names are case-insensitive; a continuation line has none.
      def field_name(line)
        line[FIELD_NAME, :name]&.downcase
      end

      def recipient_from(block)
        fields = FIELDS.transform_values { |pattern| unfolded(block)[pattern, :value]&.strip }

        Recipient.new(**fields, failed_recipient: attributable_address)
      end

      def unfolded(block)
        block.gsub(/\r?\n[ \t]+/, " ")
      end

      # The mail gem parses and decodes lazily, so unreadable input raises here
      # rather than at construction.
      def delivery_status
        @mail&.all_parts&.find { |part| DELIVERY_STATUS_TYPES.include?(part.mime_type) }&.body&.decoded
      rescue StandardError
        nil
      end
  end
end
