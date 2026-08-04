module MailBounce
  # Enhanced status code (RFC 3463): class.subject.detail.
  class Status
    # Only where a status belongs — not dotted quads in diagnostics (5.1.1.10
    # is an address). Misses a bare `smtp; 5.1.1 …`; that deferral is cheaper
    # than retiring a mailbox over a host IP read as a status.
    PATTERN = /
      (?: \A[ \t]* | [245]\d\d[ \t\-]+ | ^Status[ \t]*:[ \t]* )
      (?<code>[245]\.\d{1,3}\.\d{1,3}) (?!\.\d)
    /xi

    PERMANENT_CLASS = "5".freeze

    TRANSIENT_CLASS = "4".freeze

    def self.parse(text)
      if code = text.to_s[PATTERN, :code]
        new(code)
      end
    end

    attr_reader :code

    def initialize(code)
      @code = code.to_s
    end

    def permanent?
      status_class == PERMANENT_CLASS
    end

    def transient?
      status_class == TRANSIENT_CLASS
    end

    # Class dropped: 5.1.1 and 4.1.1 share condition "1.1".
    def condition
      parts.drop(1).join(".")
    end

    def subject
      parts[1].to_s
    end

    def to_s
      code
    end

    private
      def status_class
        parts.first.to_s
      end

      def parts
        @parts ||= code.split(".")
      end
  end
end
