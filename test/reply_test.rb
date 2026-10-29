require "test_helper"
require "json"

class MailBounce::ReplyTest < MailBounce::TestCase
  SENDING_IP = "203.0.113.9".freeze

  def test_each_reply_is_read_as_what_it_was_about
    replies.each do |reply|
      rejection = classify(reply)

      assert_equal reply["category"].to_sym, rejection.category, reply["response"]
      assert_equal reply["permanent"], rejection.permanent?, reply["response"]
      assert_equal reply.fetch("about_us", false), rejection.about_us?, reply["response"]
      assert_equal reply.fetch("slow_down", false), rejection.slow_down?, reply["response"]
      assert_equal reply.fetch("blocklisted", false), rejection.blocklisted?, reply["response"]
    end
  end

  # Most statuses in the data were filed by hand and appear nowhere in the reply.
  def test_a_status_carried_in_the_reply_is_the_one_read
    replies.select { |reply| reply["status"] && reply["response"].include?(reply["status"]) }.each do |reply|
      assert_equal reply["status"], classify(reply).status.to_s, reply["response"]
    end
  end

  private
    def replies
      JSON.parse(fixture("replies.json"))["replies"]
    end

    def classify(reply)
      MailBounce.classify(response: reply["response"], sending_ip: SENDING_IP)
    end
end
