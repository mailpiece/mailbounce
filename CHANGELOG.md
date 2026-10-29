# Changelog

## 0.6.0

- `Rejection#blocklisted?` says whether a reply names a blocklist or the sending IP's reputation, and `Rejection#slow_down?` whether the server asks the sender to send less, leaving out a mailbox receiving too much mail and a rate limit over authentication. Neither checks the sending IP; pair them with `about_us?`.
- A reply whose status calls the address invalid, such as `550 5.1.1` or `550 5.2.1`, but whose wording names a rate, a quota or a policy error no longer reads as `:invalid`; it reads as `:full`, `:blocked` or `:unknown`.
- A reply with no status that names a rate, DMARC, SPF, DKIM, a PTR record, a block listing, a policy, spoofing, banned content, a virus or an invalid sender reads as `:blocked`.
- "overquota" written as one word reads as a full mailbox.
- Mail.ru's disabled account and Yahoo's disabled or missing mailbox read as `:invalid`.
- An enhanced status one word past a reply code of its class, as in `450 cuda_nsu 4.7.1`, or written `(#5.7.1)`, is read, and a number that merely ends in a reply code is no longer taken for one.

## 0.5.1

- A report's diagnostic such as `smtp; 550 User unknown` is read by its reply code, so it reports `permanent?`.
- Checking a reply for the sending address takes time in step with its length; a long run of hex digits took quadratic time, in a bounce report anyone can send.
- A reply saying only that a quota was exceeded no longer reads as a full mailbox, since a sender's sending quota says the same.

## 0.5.0

- Initial public release.