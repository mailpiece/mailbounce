require "test_helper"

class MailBounce::RejectionTest < MailBounce::TestCase
  SENDING_IP = "203.0.113.9".freeze

  def test_a_condition_naming_the_mailbox_is_about_the_recipient
    %w[ 5.1.1 5.1.3 5.1.6 5.2.1 ].each do |status|
      assert_equal :invalid, classify("#{status} <someone@example.com>: recipient rejected").category, status
    end
  end

  def test_a_full_mailbox_is_its_own_condition_since_the_address_is_real
    assert_equal :full, classify("5.2.2 Mailbox full").category
  end

  # RFC 7505: the domain declared, via DNS, that it will never accept mail —
  # as lasting a fact as a dead mailbox.
  def test_a_null_mx_is_as_lasting_a_fact_as_a_dead_mailbox
    assert_equal :invalid, classify("5.1.10 Recipient address has null MX").category
  end

  def test_a_message_too_large_says_nothing_about_the_address
    assert_equal :oversized, classify("5.2.3 Message length exceeds administrative limit").category
    assert_equal :oversized, classify("5.3.4 Message too big for system").category
  end

  def test_network_system_protocol_and_policy_subjects_describe_the_exchange
    %w[ 5.3.2 5.4.1 5.5.0 5.7.1 ].each do |status|
      assert_equal :blocked, classify("#{status} Message refused").category, status
    end
  end

  def test_a_response_quoting_our_own_address_is_about_us_whatever_it_claims
    rejection = classify("5.1.1 rejected because #{SENDING_IP} is on a blocklist", sending_ip: SENDING_IP)

    assert_equal :blocked, rejection.category
    assert rejection.about_us?
  end

  def test_any_of_several_sending_addresses_counts_as_our_own
    rejection = classify("5.7.1 #{SENDING_IP} is listed", sending_ip: [ "198.51.100.4", SENDING_IP ])

    assert_equal :blocked, rejection.category
  end

  def test_a_response_naming_a_stranger_is_not_about_us
    refute classify("5.7.1 198.51.100.4 is listed", sending_ip: SENDING_IP).about_us?
  end

  # Addresses are compared as addresses: ours is a substring of a stranger's,
  # and a server may spell out one we hold in short form.
  def test_an_address_merely_containing_ours_is_a_stranger
    rejection = classify("550 5.1.1 blocked by 203.0.113.90", sending_ip: SENDING_IP)

    refute rejection.about_us?
    assert_equal :invalid, rejection.category
  end

  def test_our_own_address_counts_however_it_is_spelled
    assert classify("550 blocked 2001:db8:0:0:0:0:0:1 listed", sending_ip: "2001:db8::1").about_us?
    assert classify("550 blocked 2001:db8::1 listed", sending_ip: "2001:db8:0:0:0:0:0:1").about_us?
    assert classify("550 [#{SENDING_IP}] listed", sending_ip: SENDING_IP).about_us?
  end

  # A server on IPv6 names an IPv4 sender in mapped form, and either side may
  # be the one holding it that way — read as text, neither matches the other.
  def test_an_address_mapped_into_ipv6_is_the_same_host
    mapped = "::ffff:#{SENDING_IP}"

    assert classify("550 5.1.1 rejected because #{mapped} is listed", sending_ip: SENDING_IP).about_us?
    assert classify("550 5.1.1 rejected because #{SENDING_IP} is listed", sending_ip: mapped).about_us?
    assert_equal :blocked, classify("550 5.1.1 rejected because #{mapped} is listed", sending_ip: SENDING_IP).category
  end

  def test_wording_that_is_not_an_address_is_not_read_as_one
    refute classify("550 rejected at 10:30:45", sending_ip: SENDING_IP).about_us?
  end

  # A diagnostic naming an unreachable host would otherwise read as a status
  # and retire an address nothing was wrong with.
  def test_a_host_named_in_the_wording_does_not_stand_in_for_a_status
    assert_equal :unknown, classify("421 connecting to 5.1.1.10: Connection refused").category
    assert_equal :full, classify("Connected to 5.1.1.1 but mailbox full").category
    assert_equal :blocked, classify("421 connecting to 4.2.2.1 blocked").category
  end

  # The system is as dead as a mailbox when the server says so permanently;
  # one merely out of reach comes back transient, and defers on the class.
  def test_a_bad_destination_system_is_about_the_address
    permanent = classify("550 5.1.2 Bad destination system address")
    transient = classify("451 4.1.2 Host unreachable")

    assert_equal :invalid, permanent.category
    assert permanent.permanent?
    assert_equal :invalid, transient.category
    refute transient.permanent?
  end

  def test_a_server_sending_no_enhanced_status_is_read_by_its_wording
    assert_equal :invalid, classify("No such user here").category
    assert_equal :invalid, classify("Recipient not found").category
    assert_equal :full, classify("User is over quota").category
    assert_equal :full, classify("Quota exceeded").category
    assert_equal :full, classify("Mailbox size limit exceeded").category
    assert_equal :full, classify("User has exceeded storage allocation").category
    assert_equal :oversized, classify("Message too large").category
    assert_equal :oversized, classify("Message exceeds the maximum size").category
    assert_equal :blocked, classify("Message identified as spam").category
  end

  def test_an_unrecognized_condition_yields_to_wording_that_names_the_cause
    assert_equal :invalid, classify("5.0.0 User unknown in relay recipient table").category
  end

  # RFC 5321 uses "mailbox unavailable" for both 450 and 550 (busy, policy,
  # or not found), so bare text is not enough — enhanced status decides.
  def test_a_missing_mailbox_is_read_however_the_server_words_it
    assert_equal :unknown, classify("550 Requested action not taken: mailbox unavailable").category
    assert_equal :invalid, classify("550 5.1.1 Requested action not taken: mailbox unavailable").category
    assert_equal :invalid, classify("550 Invalid recipient").category
    assert_equal :invalid, classify("550 No such recipient here").category
    assert_equal :invalid, classify("550 unknown user").category
  end

  def test_mailbox_unavailable_alone_is_not_a_full_mailbox_either
    assert_equal :full, classify("550 mailbox full - mailbox unavailable").category
  end

  # Each names its own subject, so a rejection about the sender cannot be
  # phrased around it — servers say "sender address", never "sender mailbox".
  def test_none_of_that_wording_can_be_turned_against_the_sender
    assert_equal :unknown, classify("550 Sender address unavailable").category
    assert_equal :unknown, classify("550 No such sender here").category
    assert_equal :unknown, classify("550 unknown sender").category
    assert_equal :unknown, classify("550 Sender unknown").category
  end

  # Wording that names no address names ours as readily as theirs, and a
  # sender's address being gone says nothing about the mailbox we wrote to.
  def test_wording_that_names_whose_address_failed_is_the_only_wording_read
    assert_equal :unknown, classify("550 Sender domain does not exist").category
    assert_equal :unknown, classify("550 Sender address does not exist").category
    assert_equal :unknown, classify("550 MAIL FROM address does not exist").category
  end

  # The phrase attaches to whichever noun precedes it, so a recipient reading
  # is given up along with the sender ones rather than qualified again.
  def test_a_bare_predicate_names_nobody_even_where_it_meant_the_recipient
    assert_equal :unknown, classify("550 Recipient does not exist").category
    assert_equal :unknown, classify("550 Mailbox does not exist").category
  end

  # A server phrasing it that way is read by its status instead.
  def test_a_status_reads_what_the_dropped_wording_no_longer_does
    assert_equal :invalid, classify("550 5.1.1 Recipient address does not exist").category
    assert_equal :blocked, classify("550 5.1.8 Sender address does not exist").category
    assert_equal :blocked, classify("550 5.7.1 Address does not exist").category
  end

  # 1.7 and 1.8 name the sender's address, so the wording never gets a say.
  def test_a_status_naming_the_senders_address_is_not_about_the_recipient
    assert_equal :blocked, classify("550 5.1.8 Sender domain does not exist").category
    assert_equal :blocked, classify("550 5.1.7 Bad sender mailbox address").category
  end

  def test_a_policy_refusal_reads_as_blocked_however_it_is_worded
    assert_equal :blocked, classify("550 5.7.1 The address you tried does not exist").category
  end

  def test_a_rejection_matching_nothing_is_unknown_rather_than_guessed
    assert_equal :unknown, classify("Some entirely novel refusal").category
  end

  def test_a_transport_failure_with_no_server_response_at_all_is_unknown
    assert_equal :unknown, classify("No SMTP servers available").category
  end

  def test_an_empty_response_is_unknown
    assert_equal :unknown, classify("").category
    assert_equal :unknown, classify(nil).category
  end

  # The two disagree exactly where it matters: a server is permanent about a
  # listing that lapses, and the caller decides which to believe.
  def test_what_the_server_claimed_is_reported_apart_from_what_it_was_about
    rejection = classify("550 5.7.1 Service unavailable; client host blocked")

    assert rejection.permanent?
    assert_equal :blocked, rejection.category
  end

  def test_a_transient_class_is_not_permanent_however_it_is_categorized
    rejection = classify("452 4.2.2 Mailbox full")

    refute rejection.permanent?
    assert_equal :full, rejection.category
  end

  def test_a_reply_code_stands_in_when_no_enhanced_status_is_given
    assert classify("550 User unknown").permanent?
    refute classify("451 Try again later").permanent?
  end

  def test_a_response_with_neither_code_nor_status_claims_no_permanence
    refute classify("Connection reset by peer").permanent?
  end

  def test_the_enhanced_status_is_exposed_as_it_was_sent
    assert_equal "5.1.1", classify("550 5.1.1 User unknown").status.to_s
    assert_nil classify("Connection reset by peer").status
  end

  private
    def classify(response, sending_ip: nil)
      MailBounce.classify(response: response, sending_ip: sending_ip)
    end
end
