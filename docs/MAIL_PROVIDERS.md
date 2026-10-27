# Mail providers: SMTP with an app password (Phase 4)

Verified on **2026-10-26** by opening the pages named below (not from memory).
"NOT CONFIRMED" means the page was opened or searched and the fact was not
there; nothing in this file was filled in from memory. Where an official page
shows no date, the date of verification is the only date.

The app sends with **SMTP and an app password** for development and for the
first versions, and the official OAuth route is planned for the public release
(`MAIL_OAUTH_PLAN.md`). The share route (`ACTION_SEND`) is the fallback that
needs no password at all.

## Summary

| | Gmail | Outlook.com (personal) | Yahoo |
|---|---|---|---|
| SMTP host | `smtp.gmail.com` | `smtp-mail.outlook.com` | `smtp.mail.yahoo.com` |
| Port and encryption | 465 SSL, or 587 with STARTTLS | 587, STARTTLS | 465 or 587, "Requires SSL" (the word STARTTLS is not on the page) |
| User name | full address (see below) | full address | full address |
| App password | yes, needs 2-Step Verification | **NOT CONFIRMED for SMTP** (see below) | yes |
| Official size limit | 25 MB (attachments) | 20 MB or 25 MB (two pages disagree) | NOT CONFIRMED |
| Limit used by the app | 25 000 000 B | 20 000 000 B | 20 000 000 B (assumed) |
| UI | normal | warning + share is suggested | normal, size limit is an assumption |

## Gmail

- **Host, ports, encryption.** "The outgoing SMTP server, `smtp.gmail.com`,
  supports TLS." "If your client begins with plain text before issuing the
  `STARTTLS` command, use port `465` (for SSL) or port `587` (for TLS)."
  <https://developers.google.com/workspace/gmail/imap/imap-smtp> (2026-10-26).
  The same page: SMTP also supports OAuth 2.0 with SASL XOAUTH2.
- **User name.** NOT CONFIRMED for a personal account on an official page. The
  Workspace admin page says the user name is the full address (summary of
  <https://knowledge.workspace.google.com/admin/gmail/send-email-from-a-printer-scanner-or-app>);
  the app uses the full address.
- **Less secure apps.** <https://support.google.com/accounts/answer/6010255>:
  "Starting January 2025, less secure apps, third-party apps, or devices that
  have you sign in with only your username and password will no longer be
  supported for Google Workspace accounts", and it recommends "Sign in with
  Google". An exact date for personal accounts: NOT CONFIRMED.
  <https://support.google.com/mail/answer/7126229>: "Gmail no longer supports
  third-party apps or devices which require you to share your Google username
  and password."
- **App passwords.** <https://support.google.com/accounts/answer/185833>: "An
  app password is a 16-digit passcode that gives a less secure app or device
  permission to access your Google Account." "App passwords can only be used
  with accounts that have 2-Step Verification turned on." The option can be
  missing when 2-Step Verification is "set up only for security keys", for
  work, school or other organisation accounts, and with Advanced Protection.
  The page calls them "not recommended and unnecessary in most cases" and
  says they are revoked when the account password changes. The page links to
  <https://myaccount.google.com/apppasswords> (the page itself could not be
  read: "Your browser is not supported anymore"), so the menu names of the
  creation steps are **NOT CONFIRMED**; the user instructions in the app say
  "open the app passwords page of your Google Account" and do not invent menu
  names. Whether SMTP is named as a use of app passwords: NOT CONFIRMED (the
  page does not name SMTP).
- **2-Step Verification** is turned on from the Google Account, "Security &
  sign-in", then "Turn on 2-Step Verification"
  (<https://support.google.com/accounts/answer/185839>).
- **Size.** <https://support.google.com/mail/answer/6584>: "For personal Gmail
  accounts, the limit is 25 MB." Above it Gmail turns the attachment into a
  Drive link. Whether the 25 MB counts the encoded message: NOT CONFIRMED (the
  page says "total attachment size"). The SMTP `SIZE` value of
  `smtp.gmail.com`: NOT CONFIRMED.
- **Sending limits.** <https://support.google.com/mail/answer/22839>: a block
  is possible when a user sends to "more than 500 recipients in a single email
  and or more than 500 emails sent in a day". One scan is one message to one
  recipient.

## Outlook.com (personal Microsoft accounts)

- **Host, port, encryption.**
  <https://support.microsoft.com/en-us/outlook/pop-imap-and-smtp-settings-for-outlook-com>
  (no date shown, 2026-10-26): SMTP server `smtp-mail.outlook.com`, port 587,
  encryption STARTTLS, user name "your email address".
- **The same page lists the SMTP authentication method as "OAuth2/Modern
  Auth" and says "Outlook.com requires the use of Modern Auth / OAuth2."** In
  the password row it also says "Your Microsoft account password. If your
  password is not being recognized, or if you want to add your Outlook.com
  account to a smart device like a home security camera, you may need an app
  password." The page does not reconcile the two.
- **Basic authentication.**
  <https://support.microsoft.com/en-us/support/known-issues/modern-authentication-methods-now-needed-to-continue-syncing-outlook-email-in-non-microsoft-email-ap>
  ("Last Updated: June 10, 2024", applies to Outlook.com): "September 16th,
  2024 - Basic Authentication no longer available to access any Outlook
  account" and "After September 16th, users attempting to connect their
  Microsoft accounts through Basic Authentication will fail to do so." The
  Exchange Online (business) page
  <https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/deprecation-of-basic-authentication-exchange-online>
  (ms.date 2026-07-10) is about business tenants, and says "The deprecation of
  basic authentication also prevents the use of app passwords with apps that
  don't support two-step verification." It is not about personal accounts.
- **App passwords.**
  <https://support.microsoft.com/en-us/account-billing/how-to-get-and-use-app-passwords-5896ed9b-4263-e681-128a-a6f2979a7944>:
  "You only need to create an app password if you have two-step verification
  turned on and are using a device that doesn't support it." Steps: "Go to the
  Advanced security options of your Microsoft account dashboard and scroll
  down to the App passwords section." then "Create password".
- **Verdict: an app password for SMTP on a personal Outlook.com account is NOT
  CONFIRMED, and the pages above point the other way** (Basic authentication
  is stated as ended on 2024-09-16; the SMTP table asks for OAuth2). The app
  therefore (a) lets the user try it, because the app-password page exists for
  personal accounts, (b) shows a warning in Settings and on a failed send that
  Outlook.com may refuse a password and that the share route works without
  one, and (c) never claims that it works. **This needs a real test by the
  user** (step in `PHASE_4_VALIDATION.md`).
- **Size.** <https://support.microsoft.com/en-us/outlook/sending-limits-in-outlook-com>
  (no date shown): "The attachment size limit for files is 25 MB." A search
  snippet of <https://support.microsoft.com/en-us/outlook/reduce-attachment-size-to-send-large-files-with-outlook>
  says "For internet email accounts such as Outlook.com or Gmail, the email
  size limit is 20 megabytes (MB)" (only the snippet was read, not the page).
  Two numbers, so the app uses the smaller one (20 MB).
- **Sending limits.** The same page gives numbers for Microsoft 365
  subscribers only; "will be lower for non-subscribers"; the free numbers are
  NOT CONFIRMED.

## Yahoo Mail

- **Host and ports.** <https://help.yahoo.com/kb/SLN4075.html>: SMTP server
  `smtp.mail.yahoo.com`, "Port - 465 or 587", "Requires SSL - Yes", "Requires
  authentication - Yes", user name "Your full email address". The page does
  not use the word STARTTLS; <https://help.yahoo.com/kb/SLN4724.html> says
  "Requires TLS - Yes (if available)". The app uses 465 with implicit SSL,
  which the page states without a condition.
- **App passwords.** <https://help.yahoo.com/kb/SLN15241.html> ("Generate and
  manage 3rd-party app passwords"): "Third-party email apps (that do not use
  our Yahoo branded sign-in page) require you to enter a single password for
  login credentials." Steps: sign in to the Yahoo Account Security page
  (<https://login.yahoo.com/account/security>); under "External connections"
  click "Create app password"; enter the app's name; click "Generate
  password"; use the one-time password; click "Done". "App passwords remain
  active - even if you change your main account password. To invalidate an app
  password you must delete it." Eligibility: "use a browser that you've used
  to sign into Yahoo for several days in a row and avoid using Incognito
  mode." Format and length: NOT CONFIRMED. Two-step verification as a
  requirement: not on this page;
  <https://help.yahoo.com/kb/fix-pop-imap-client-sending-receiving-issues-sln3792.html>
  says an app password "is required if you've enabled Yahoo account key or
  two-step verification". An unverified address can cause a 553 error from a
  third-party app (same page).
- **Size and sending limits.** NOT CONFIRMED: no official Yahoo page that was
  reachable states an attachment size or a sending limit
  (<https://help.yahoo.com/kb/SLN5223.html>, `SLN2229`, `SLN24012` were
  missing or unrelated). The app assumes the smallest confirmed number of the
  other providers, 20 MB, and says so in the settings text.

## The size limit in the app (conservative)

The limits above are on the **message**. A PDF travels as base64 inside MIME:
every 3 bytes become 4 characters, plus a line break after every 76
characters, so the message is about **1.37 times** the file (the Google page on
receiving limits also says the encoding "adds about a 37% increase",
<https://knowledge.workspace.google.com/admin/gmail/gmail-receiving-limits-in-google-workspace>,
2026-10-26). `MailSizePolicy` in `lib/domain/mail/mail_size_policy.dart` keeps the
numbers:

```
maxPdfBytes = floor((maxMessageBytes - 64 KiB for headers and body) / 1.37)
Gmail   25 000 000 B message  ->  about 18.2 MB of PDF
Outlook 20 000 000 B message  ->  about 14.6 MB of PDF
Yahoo   20 000 000 B message  ->  about 14.6 MB of PDF (assumed)
```

A bigger PDF is not sent: the screen says so, and offers the share route (the
mail app decides what to do with a large file, for example a Drive link).
SMTP replies 552 are mapped to the same message, in case a limit is lower than
the number above.

## Sending model

- SMTP is used only after a tap on "Send"; no automatic sending (Phase 7).
- The account that sends is the one in Settings (which can be a different
  account from the one on the phone, so the user's own "Sent" folder does not
  fill up). If the destination is "my own address" the message goes to the
  same account.
- The message has one attachment (the PDF), a short fixed body and the subject
  `One Click Scan - <stem>`; the OCR text is never in the mail (ADR-019,
  ADR-020).

## Phase 4.1: app packages, guide pages, diagnostics

Verified on **2026-10-27**. The app uses these facts in the share route (open the
provider's own e-mail app first) and in the guide of Settings (the button that
opens the page where the user makes an app password).

### The guide pages

| Provider | Page the button opens (`https`, nothing added) | Source | What the source says |
|---|---|---|---|
| Gmail | `https://myaccount.google.com/apppasswords` | Google Account Help, "Sign in with app passwords" (`https://support.google.com/accounts/answer/185833`), read 2026-10-27 | The page links it: "Create and manage your app passwords ... You may need to sign in to your Google Account." Prerequisite: "App passwords can only be used with accounts that have 2-Step Verification turned on." Missing option when: 2-Step Verification only for security keys, a work, school or other organization account, or Advanced Protection. |
| Yahoo | `https://login.yahoo.com/account/security` | Yahoo Help, "Generate and manage 3rd-party app passwords" (`https://help.yahoo.com/kb/SLN15241.html`), read 2026-10-27 | Steps: "Sign in to your Yahoo Account Security page." Under "External connections" click "Create app password"; enter the name of the app; click "Generate password"; use the one-time password; click "Done". Also: use a browser you have used to sign in to Yahoo for several days in a row and avoid Incognito mode. |
| Outlook | none | `MAIL_PROVIDERS.md` (Outlook.com) | An app password for SMTP is not confirmed (the main unknown of Phase 4); the app shows no steps, only that Outlook waits for OAuth, and offers the backup way. |

What is **not** in those pages, so the app does not claim it as a fact of the
provider: the Google page gives no click path and no names of menus (only the
link), and does not say the password is shown once or whether it has spaces; the
Yahoo page does not mention 2-step verification and does not say the password
is shown once. The "shown only once, paste it without spaces" reminder of the
guide is a precaution of the app, not a quotation (Yahoo calls it a "one-time
password"). The guide therefore gives the Gmail steps in general words and the
address only, and uses the Yahoo menu names exactly as the Yahoo page writes them
(in English). The pages of the providers change: the text says so.

### The app packages (share route)

| Provider | Package | Confirmed from an official source? |
|---|---|---|
| Gmail | `com.google.android.gm` | **No.** |
| Outlook | `com.microsoft.office.outlook` | **No.** |
| Yahoo Mail | `com.yahoo.mobile.client.android.mail` | **No.** |

The official place for a package name is the Google Play listing of the app
(`https://play.google.com/store/apps/details?id=<package>`). Fetching those three
pages on 2026-10-27 returned a 200 reply with an empty body (the page is built by
script), so **nothing could be read from them**. The names were then found only
in non-official places: APK mirror sites (APKMirror lists all three, Softpedia the
Yahoo one), a book chapter on Android forensics (Gmail), and setup guides of a
university and of a hosting company that link to the Play listing of the Outlook
package. They agree with each other and with long-standing practice, but they
are **not** an official statement. Why this is safe: the app does not trust the
name blindly. It asks the phone whether the package is installed
(`PackageManager`), and if it is not (or the name is wrong), it falls back to the
e-mail apps that handle `mailto:`, and only then to the generic share menu. A
wrong name would mean the provider app is not picked directly, never a failure.
Step 8b of `PHASE_4_VALIDATION.md` checks on a real phone that each opens.

### What the share route asks of the phone

- `<queries>` in the manifest: the three packages above and one intent
  (`ACTION_SENDTO`, scheme `mailto`). **No** `QUERY_ALL_PACKAGES`.
- The PDF is a `content://` document URI. The intent has
  `FLAG_GRANT_READ_URI_PERMISSION` (also on the ClipData) and, for an explicit
  package, the app calls `grantUriPermission` for that package with read access
  only. Never a write grant. Whether the target app can really read the
  attachment is checked by the user (step 8b); the tests only check the intent.
- The e-mail app uses **the account it already has selected**; the app cannot
  force the sender. The texts say so.

### The diagnostic line

A failed test or send shows one line, for example `Step: authentication, code 535`
(`Στάδιο: ταυτοποίηση, κωδικός 535`): the step (connection, TLS, authentication,
sending) and the 3 digit SMTP reply code when there is one. Never an address, a
host with a user name, a password, or the text of a server reply. The step comes
from the kind of the error (a socket error or a timeout: connection; a failed
encryption: TLS; a refused sign-in: authentication; any other reply: sending).
A timeout is always shown as "connection", even if it happened later, because
the library does not say where it stopped.

## Not confirmed (list)

- Gmail: exact click path for app passwords (the page could not be read),
  whether SMTP is named there, the SMTP user name rule for personal accounts,
  the exact end date for personal accounts, whether 25 MB includes encoding.
- Outlook.com: **app password with SMTP (the main unknown)**, free-account
  sending limits, which of 20 MB and 25 MB is the real limit.
- Yahoo: STARTTLS wording, app-password format, whether two-step verification
  is required, **attachment size and sending limits**.
- **Phase 4.1:** the three app package names (no official page could be read),
  the click path and menu names of the Google page for app passwords (the page
  only links to `myaccount.google.com/apppasswords`), whether the Google and
  Yahoo passwords are shown only once, and whether Yahoo needs 2-step
  verification.
