# Changelog

## 0.5.1

- A report's diagnostic such as `smtp; 550 User unknown` is read by its reply code, so it reports `permanent?`.
- Checking a reply for the sending address takes time in step with its length; a long run of hex digits took quadratic time, in a bounce report anyone can send.
- A reply saying only that a quota was exceeded no longer reads as a full mailbox, since a sender's sending quota says the same.

## 0.5.0

- Initial public release.