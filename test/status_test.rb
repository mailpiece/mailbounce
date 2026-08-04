require "test_helper"

class MailBounce::StatusTest < MailBounce::TestCase
  def test_a_class_five_status_is_permanent
    status = MailBounce::Status.parse("550 5.1.1 User unknown")

    assert status.permanent?
    refute status.transient?
  end

  def test_a_class_four_status_is_transient
    status = MailBounce::Status.parse("452 4.2.2 Mailbox full")

    assert status.transient?
    refute status.permanent?
  end

  # The same condition is reported under either class, so the class is read
  # apart from what it was about.
  def test_the_condition_drops_the_class
    assert_equal "2.2", MailBounce::Status.parse("5.2.2 Mailbox full").condition
    assert_equal "2.2", MailBounce::Status.parse("4.2.2 Mailbox full").condition
  end

  def test_the_subject_is_the_middle_digits
    assert_equal "7", MailBounce::Status.parse("5.7.1 Delivery not authorized").subject
  end

  def test_a_success_status_is_neither_permanent_nor_transient
    status = MailBounce::Status.parse("250 2.0.0 OK")

    refute status.permanent?
    refute status.transient?
  end

  def test_text_carrying_no_status_parses_to_nothing
    assert_nil MailBounce::Status.parse("Connection reset by peer")
    assert_nil MailBounce::Status.parse("")
    assert_nil MailBounce::Status.parse(nil)
  end

  def test_a_version_number_is_not_a_status
    assert_nil MailBounce::Status.parse("Postfix 3.7.4 ready")
    assert_nil MailBounce::Status.parse("Postfix 5.7.4 ready")
  end

  # A diagnostic names the host it failed to reach, and an address read as a
  # status retires the recipient it was never about.
  def test_a_dotted_quad_in_the_wording_is_not_a_status
    assert_nil MailBounce::Status.parse("421 connecting to 5.1.1.10: Connection refused")
    assert_nil MailBounce::Status.parse("Connected to 5.1.1.1 but mailbox full")
    assert_nil MailBounce::Status.parse("host 4.2.2.1 refused")
  end

  # An address opening the text, or following a reply code, stands exactly
  # where a status would; only its fourth part tells them apart.
  def test_a_dotted_quad_is_not_a_status_truncated_to_three_parts
    assert_nil MailBounce::Status.parse("5.1.1.10 host unreachable")
    assert_nil MailBounce::Status.parse("550 5.1.1.10 unreachable")
    assert_nil MailBounce::Status.parse("Status: 5.1.1.10")
  end

  def test_a_status_is_read_where_one_belongs
    assert_equal "5.1.1", MailBounce::Status.parse("5.1.1 User unknown").to_s
    assert_equal "5.1.1", MailBounce::Status.parse("550 5.1.1 User unknown").to_s
    assert_equal "5.7.1", MailBounce::Status.parse("550-5.7.1 blocked").to_s
    assert_equal "5.1.1", MailBounce::Status.parse("Status: 5.1.1").to_s
    assert_equal "5.1.1", MailBounce::Status.parse("smtp; 550 5.1.1 <a@example.com>: User unknown").to_s
  end
end
