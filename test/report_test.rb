require "test_helper"

class MailBounce::ReportTest < MailBounce::TestCase
  RECIPIENT = "recipient@example.com".freeze

  def test_a_permanent_failure_names_the_recipient_as_the_reason
    recipient = report("failed.eml").for(RECIPIENT)

    assert recipient.failed?
    assert recipient.permanent?
    assert recipient.permanent_failure?
  end

  def test_a_delay_notice_is_not_a_failure_however_permanent_the_message_looks
    recipient = report("delayed.eml").for(RECIPIENT)

    refute recipient.failed?
    refute recipient.permanent_failure?
  end

  def test_a_transient_failure_is_a_failure_but_not_a_permanent_one
    recipient = report("transient-failure.eml").for(RECIPIENT)

    assert recipient.failed?
    refute recipient.permanent?
    refute recipient.permanent_failure?
  end

  def test_a_report_covering_several_recipients_speaks_only_for_the_one_it_names
    report = report("multi-recipient.eml")

    assert report.for("gone@example.com").permanent_failure?
    refute report.for(RECIPIENT).permanent_failure?
  end

  def test_every_recipient_of_a_report_is_exposed
    assert_equal %w[ gone@example.com recipient@example.com ], report("multi-recipient.eml").recipients.map(&:address)
  end

  def test_a_report_for_a_single_recipient_needs_no_name_to_speak_for_it
    assert report("unnamed-recipient.eml").for(RECIPIENT).permanent_failure?
  end

  # A caller is free to compare against false on a public method.
  def test_a_block_carrying_no_status_is_not_permanent_rather_than_unanswered
    assert_equal false, MailBounce::Recipient.new(action: "failed").permanent?
  end

  # A blank name is not a name an unnamed block answers to: on a report listing
  # several, matching it would hand back whichever block happened to omit one.
  def test_an_unnamed_block_answers_to_no_name_rather_than_to_the_empty_one
    unnamed = MailBounce::Recipient.new(action: "failed", status: "5.1.1")

    assert unnamed.anonymous?
    refute unnamed.addressed_to?("")
  end

  # Handing back a block belonging to someone else would retire an address the
  # report never mentioned.
  def test_a_report_naming_its_recipient_speaks_for_nobody_else
    assert_nil report("failed.eml").for("totally-other@example.org")
    assert_nil report("multi-recipient.eml").for("totally-other@example.org")
  end

  # A reporter that brackets an address may quote it inside the brackets too.
  def test_a_bracketed_address_names_its_recipient_all_the_same
    report = report("bracketed-recipient.eml")

    assert_equal %w[ gone@example.com quoted@example.com recipient@example.com ], report.recipients.map(&:address)
    assert report.for("gone@example.com").permanent_failure?
    assert report.for("quoted@example.com").permanent_failure?
  end

  def test_a_recipient_is_found_even_where_a_reporter_ran_the_blocks_together
    assert_equal %w[ gone@example.com recipient@example.com ], report("unseparated-recipients.eml").recipients.map(&:address)
  end

  # RFC 3464 fixes no field order, and a block whose address arrives after its
  # action must still keep the address — a block that lost it would answer to
  # any name at all.
  def test_a_block_that_opens_with_its_action_keeps_its_address
    report = report("action-first.eml")

    assert_equal [ RECIPIENT ], report.recipients.map(&:address)
    assert report.for(RECIPIENT).permanent_failure?
    assert_nil report.for("totally-other@example.org")
  end

  def test_several_blocks_opening_with_their_actions_each_keep_theirs
    report = report("action-first-recipients.eml")

    assert_equal %w[ gone@example.com recipient@example.com ], report.recipients.map(&:address)
    assert report.for("gone@example.com").permanent_failure?
    assert report.for(RECIPIENT).permanent_failure?
  end

  # RFC 3464 §2.3.2 requires Final-Recipient, but a reporter that names its
  # recipient only in Original-Recipient has still named it — and a block that
  # kept no address would answer to any name at all.
  def test_a_block_named_only_by_its_original_recipient_keeps_that_address
    report = report("original-recipient.eml")

    assert_equal [ RECIPIENT ], report.recipients.map(&:address)
    assert report.for(RECIPIENT).permanent_failure?
    assert_nil report.for("totally-other@example.org")
  end

  def test_a_block_naming_both_recipients_is_read_as_the_final_one
    recipient = report("action-first.eml").for(RECIPIENT)

    assert_equal RECIPIENT, recipient.address
    assert_equal "rfc822; #{RECIPIENT}", recipient.final_recipient
  end

  # A recipient field carrying only its type tag, or only its wrapping, names
  # nobody — so the address is taken from whichever source does name someone.
  def test_a_recipient_field_that_names_nobody_yields_to_one_that_does
    %w[ rfc822; rfc822;<> ].each do |empty|
      recipient = MailBounce::Recipient.new(action: "failed", status: "5.1.1",
        final_recipient: empty, original_recipient: "rfc822; #{RECIPIENT}")

      assert_equal RECIPIENT, recipient.address, "#{empty.inspect} should not win over a named source"
    end
  end

  # Some reporters name the failed address in a header instead of the report.
  def test_a_block_naming_nobody_takes_the_address_the_header_failed
    report = report("failed-recipients-header.eml")

    assert_equal [ RECIPIENT ], report.recipients.map(&:address)
    assert report.for(RECIPIENT).permanent_failure?
    assert_nil report.for("totally-other@example.org")
  end

  # Pairing several blocks with several header addresses by position would be a
  # guess, and a wrong guess retires someone the report never named.
  def test_a_header_naming_several_addresses_stands_in_for_none_of_them
    report = MailBounce.parse(fixture("failed-recipients-header.eml")
      .sub("X-Failed-Recipients: #{RECIPIENT}", "X-Failed-Recipients: #{RECIPIENT}, gone@example.com"))

    assert report.recipients.one?
    assert report.recipients.first.anonymous?
  end

  # Repeating the header is another way of naming several addresses.
  def test_a_header_repeated_with_another_address_stands_in_for_neither
    report = MailBounce.parse(fixture("failed-recipients-header.eml")
      .sub("X-Failed-Recipients: #{RECIPIENT}", "X-Failed-Recipients: #{RECIPIENT}\nX-Failed-Recipients: gone@example.com"))

    assert report.recipients.one?
    assert report.recipients.first.anonymous?
  end

  def test_a_repeated_header_naming_nobody_does_not_unname_the_one_that_does
    report = MailBounce.parse(fixture("failed-recipients-header.eml")
      .sub("X-Failed-Recipients: #{RECIPIENT}", "X-Failed-Recipients: #{RECIPIENT}\nX-Failed-Recipients:"))

    assert_equal [ RECIPIENT ], report.recipients.map(&:address)
    assert report.for(RECIPIENT).permanent_failure?
  end

  # The single-recipient leniency is what lets an unnamed block answer at all,
  # so it must apply only where the report names nobody anywhere. Every source
  # is read before a block is called anonymous; once one names an address, a
  # stranger asking is refused.
  def test_a_report_naming_an_address_anywhere_refuses_a_stranger
    [ "Final-Recipient: rfc822; #{RECIPIENT}",
      "Original-Recipient: rfc822; #{RECIPIENT}" ].each do |named|
      report = MailBounce.parse(delivery_status("#{named}\nAction: failed\nStatus: 5.1.1"))

      assert_equal RECIPIENT, report.for(RECIPIENT).address, named
      assert_nil report.for("totally-other@example.org"), named
    end
  end

  # A recipient field carrying no address names nobody, so such a report is as
  # unnamed as one carrying no field — there is no address to mis-attribute.
  def test_a_report_naming_nobody_at_all_is_anonymous_rather_than_misread
    [ "", "Final-Recipient: rfc822;", "Final-Recipient: rfc822; <>" ].each do |unnamed|
      report = MailBounce.parse(delivery_status("#{unnamed}\nAction: failed\nStatus: 5.1.1"))

      assert report.recipients.first.anonymous?, unnamed.inspect
    end
  end

  # A field left empty takes no value at all, rather than the next line's.
  def test_an_empty_field_does_not_take_the_following_line_for_its_value
    recipient = MailBounce.parse(fixture("empty-action.eml")).for(RECIPIENT)

    assert_nil recipient
  end

  def test_a_wrapped_diagnostic_is_reported_whole
    diagnostic = report("folded-diagnostic.eml").for(RECIPIENT).diagnostic_code

    assert_includes diagnostic, "User unknown in local recipient table"
  end

  def test_an_internationalized_report_is_read_like_any_other
    assert report("internationalized.eml").for(RECIPIENT).permanent_failure?
  end

  # An RFC 6533 report may name its recipient in raw UTF-8 while the message
  # itself is read as bytes.
  def test_an_internationalized_address_names_its_recipient_across_encodings
    report = report("internationalized-address.eml")

    assert report.for("rené@example.com").permanent_failure?
    assert report.for("RENÉ@EXAMPLE.COM").permanent_failure?
    assert_nil report.for("totally-other@example.org")
  end

  def test_a_named_recipient_is_matched_whatever_its_case
    assert report("failed.eml").for("Recipient@Example.COM").permanent_failure?
  end

  def test_the_reported_fields_travel_with_the_recipient
    recipient = report("failed.eml").for(RECIPIENT)

    assert_equal "5.1.1", recipient.status.to_s
    assert_equal "failed", recipient.action
    assert_equal "dns; mx.example.com", recipient.remote_mta
    assert_includes recipient.diagnostic_code, "User unknown"
  end

  def test_a_report_with_no_machine_readable_part_claims_nothing
    report = report("unstructured.eml")

    refute report.any?
    assert_nil report.for(RECIPIENT)
  end

  def test_a_part_that_cannot_be_decoded_claims_nothing_rather_than_raising
    report = report("bogus-encoding.eml")

    refute report.any?
    assert_nil report.for(RECIPIENT)
  end

  def test_something_that_is_not_a_message_at_all_claims_nothing
    refute MailBounce.parse("not a bounce").any?
    refute MailBounce.parse("").any?
    refute MailBounce.parse(nil).any?
  end

  # A block ends where a field repeats, which once meant reading the whole of
  # it again per line — quadratic, on a notice anyone can send us.
  def test_a_report_of_many_distinct_fields_is_read_in_step_with_its_length
    elapsed = Time.now
    MailBounce.parse(delivery_status((1..4_000).map { |i| "#{"F" * 200}#{i}: v" }.join("\r\n") + "\r\nAction: failed")).recipients

    assert_operator Time.now - elapsed, :<, 1, "the block was read again for every line it holds"
  end

  def test_a_report_past_the_ceiling_reports_nothing
    oversized = delivery_status("Final-Recipient: rfc822; #{RECIPIENT}\r\nAction: failed")

    assert MailBounce.parse(oversized).any?
    refute MailBounce.parse(oversized, max_size: 100).any?
  end

  private
    def report(name)
      MailBounce.parse(fixture(name))
    end

    def delivery_status(block)
      <<~REPORT.gsub("\n", "\r\n")
        Content-Type: multipart/report; report-type=delivery-status; boundary="BB"

        --BB
        Content-Type: message/delivery-status

        Reporting-MTA: dns; mx.example.com

        #{block}

        --BB--
      REPORT
    end
end
