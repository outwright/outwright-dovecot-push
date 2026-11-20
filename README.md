# Outwright push for Dovecot

New-mail notifications for [Outwright](https://outwright.app) on Dovecot 2.4 and 2.3: a small
Lua script for Dovecot's `push_notification` plugin. The guide is also at
[outwright.app/push/dovecot](https://outwright.app/push/dovecot).

**Outwright is in alpha.** To join, sign up on [outwright.app](https://outwright.app/#join) and
install it straight away with TestFlight.

## What it does

Dovecot has no way for a mail app to ask for push by itself, so the server needs this script.
When mail is delivered to someone's Inbox, it tells Outwright's push relay, and the relay wakes
that person's iPhone. The phone then fetches the sender and subject from your server, as it does
any other time.

The script sends nothing of the mail: no sender, subject, text or address. Each phone that
switches push on writes its push address into the user's private IMAP METADATA (RFC 5464), and
the script posts to the addresses it finds there. It only ever posts to the push relay: an
address that points anywhere else is ignored, so a user cannot make your server send requests
elsewhere. Push is part of the paid app, and each user switches it on in the
app's settings for their account.

## What you need

- Dovecot 2.4 or 2.3, delivering mail over LMTP or LDA.
- Dovecot's Lua plugins, which are part of `dovecot-core` on Debian and Ubuntu.

## Install

```sh
mkdir -p /usr/local/share/outwright
cp outwright-push.lua /usr/local/share/outwright/
```

Then add the config file for your version, `90-outwright-push-2.4.conf` or
`90-outwright-push-2.3.conf`, as `/etc/dovecot/conf.d/90-outwright-push.conf`, and run
`doveadm reload`.

## Check that it works

Switch on Notifications for the account in Outwright. The app saves a small check message to the
Inbox, already read and deleted, and removes it again within seconds; the switch stays on only
when the script answered through the relay. If it says the server is not set up for push, look
for `outwright push` in Dovecot's log.

## Licence

MIT or Apache-2.0, at your option.
