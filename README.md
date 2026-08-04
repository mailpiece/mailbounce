# mailbounce

📭 Email delivery failures for Ruby.

Classify a rejected message and read delivery status notifications, so you know whose fault a bounce was.

**mailbounce** reads the two ways mail comes back: a rejection during the SMTP session, and a delivery status notification (RFC 3464) arriving afterwards.

For senders deciding what to do after a bounce: suppression-list logic that shouldn't retire an address over a blocklisted IP, retry queues that need to tell a full mailbox from a dead one, deliverability dashboards categorizing bounces at scale.

**mailbounce** handles:

- classification — enhanced status code first, then wording, so a bare `5.0.0` paired with a diagnostic still resolves
- five categories — invalid, full, oversized, blocked, unknown — what the bounce is actually about, not just its status code
- sending IP awareness — tells a blocklisted IP apart from a real recipient failure
- permanent vs category kept separate — what the server claimed and what the rejection was about, reported independently so you decide which to trust
- delivery status notification parsing — recipients, actions, diagnostic codes, remote MTA, per RFC 3464
- size-capped parsing — bounces capped to 1 MB by default, adjustable

> mailbounce reports what a failure is. Retiring an address, retrying, and how long to remember either stay in your code.



## Contents

- [Installation](#installation)
- [Classifying a Rejection](#classifying-a-rejection)
- [Categories](#categories)
- [Status](#status)
- [Permanent Is Not the Same as Final](#permanent-is-not-the-same-as-final)
- [Reading a Report](#reading-a-report)
- [Testing](#testing)
- [History](#history)
- [Contributing](#contributing)
- [License](#license)



## Installation

Add this line to your application's Gemfile:

```ruby
gem "mailbounce"
```

Requires Ruby >= 3.4

## Classifying a Rejection

```ruby
rejection = MailBounce.classify(response: "550 5.1.1 <someone@example.com>: User unknown",
  sending_ip: "203.0.113.9")

rejection.category    # => :invalid
rejection.status.to_s # => "5.1.1"
rejection.permanent?  # => true
rejection.about_us?   # => false - the response doesn't quote our own sending IP (see Categories)
```

- **response** - the SMTP reply, or a diagnostic taken from a report
- **sending_ip** - optional, the address the mail went out from



## Categories


| Category     | What it means                                                                              |
| ------------ | ------------------------------------------------------------------------------------------ |
| `:invalid`   | The mailbox doesn't exist - the one category that says something lasting about the address |
| `:full`      | The mailbox exists and is over quota                                                       |
| `:oversized` | This message was too large; another might not be                                           |
| `:blocked`   | Policy, reputation, or the network - about the exchange, not the address                   |
| `:unknown`   | Nothing matched                                                                            |


Classification reads the enhanced status code first, then falls back to wording, since plenty of servers pair a bare `5.0.0` with a diagnostic that names the cause.

Unmatched rejections come back `:unknown` rather than as a guess.

Giving `sending_ip` is what makes the interesting case work. A server quoting the address the mail came from is describing the sender, so it classifies `:blocked` however firmly it talks about the recipient:

```ruby
MailBounce.classify(response: "550 5.1.1 rejected because 203.0.113.9 is on a blocklist",
  sending_ip: "203.0.113.9").category
# => :blocked, not :invalid
```

Without it, that response reads as a recipient failure - and retiring an address over someone else's opinion of your IP is the mistake this library exists to prevent.

## Status

`rejection.status` and `recipient.status` return a `MailBounce::Status` — the parsed RFC 3463 enhanced code (`class.subject.detail`), not just the string it came from. It's `nil` when the response or field carried no enhanced code to parse.

```ruby
status = rejection.status

status.to_s        # => "5.1.1"
status.permanent?  # => true  - class 5
status.transient?  # => false - class 4
status.subject     # => "1"   - the subject digit
status.condition   # => "1.1" - subject.detail, with the class dropped
```

`condition` is what to compare across a permanent/transient pair that means the same thing: `5.1.1` and `4.1.1` are both "mailbox unavailable", one lasting and one not, and both read `"1.1"`.

## Permanent Is Not the Same as Final

`permanent?` reports what the server claimed: a 5xx is permanent, per RFC 3463. `category` reports what the rejection was about. They disagree exactly where it matters:

```ruby
rejection = MailBounce.classify(response: "550 5.7.1 Service unavailable; client host blocked")

rejection.permanent?  # => true - the server said so
rejection.category    # => :blocked - but a listing lapses
```

Both are reported so a caller can decide which to believe. This library doesn't decide for you.

## Reading a Report

```ruby
report = MailBounce.parse(raw_bounce)

report.any?         # => true, when there's a machine-readable part to read
report.recipients   # => [#<MailBounce::Recipient ...>]

recipient = report.for("someone@example.com")
recipient.action             # => "failed"
recipient.status.to_s        # => "5.1.1"
recipient.permanent?         # => true
recipient.permanent_failure? # => true - failed, and permanently
recipient.diagnostic_code    # => "smtp; 550 5.1.1 ... User unknown"
recipient.remote_mta         # => "dns; mx.example.com"
```

| Accessor | Notes |
| --- | --- |
| `address` | the recipient's mailbox, read from `Final-Recipient`, `Original-Recipient`, or `X-Failed-Recipients` in that order; `""` if none named it |
| `anonymous?` | `true` when `address` is empty |
| `final_recipient` / `original_recipient` | the raw RFC 3464 fields this block carried, unparsed |
| `action` | e.g. `"failed"`, `"delayed"`, `"delivered"` |
| `failed?` | `action` compared case-insensitively to `"failed"` |
| `status` | the enhanced code as a `MailBounce::Status`, or `nil` |
| `permanent?` | `status&.permanent?`, `false` when there's no status |
| `permanent_failure?` | `failed? && permanent?` — usually the question worth asking |
| `diagnostic_code` / `remote_mta` | raw diagnostic and reporting-MTA fields, unparsed |
| `addressed_to?(address)` | used internally by `Report#for`; encoding-aware, case-insensitive comparison |

Reports announce delays and successes by the same route and in the same shape, so `permanent_failure?` is usually the question worth asking - `Action: delayed` is not a bounce however permanent the covering message reads.

A report naming several recipients speaks for a given address only when it names it; one covering a single recipient needn't name anyone. Nothing raises: a report with no machine-readable part, or bytes that aren't a message at all, reports nothing.

Bounces are capped to 1 MB. Past that a report is refused like any other it can't read. Lower it where you'd rather hold less:

```ruby
MailBounce.parse(raw_bounce, max_size: 64 * 1024)
```



## Testing

```sh
bundle install
rake
```



## History

View the [changelog](CHANGELOG.md).

## Contributing

Everyone is encouraged to help improve this project:

- [Report bugs](https://github.com/mailpiece/mailbounce/issues)
- Fix bugs and submit pull requests
- Write, clarify, or fix documentation
- Suggest or add new features



## Acknowledgments

View the [acknowledgments](ACKNOWLEDGMENTS.md).

## License

MIT. See [LICENSE](LICENSE).