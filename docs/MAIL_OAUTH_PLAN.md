# Mail OAuth plan (research only, nothing implemented)

Verified on **2026-10-26** from the official pages named below. "NOT CONFIRMED"
means the page was read or searched and the fact was not there. Nothing here is
from memory. Phase 4 builds no OAuth; it only keeps the door open
(`MailAuth` is sealed and `MailProvider` lists the kinds of authentication it
supports, `appPassword` today and `oauth` later), so the rest of the app does
not change when OAuth arrives.

Why a plan at all: a provider can stop SMTP with a password at any time, and
for Outlook.com it already seems to have (`MAIL_PROVIDERS.md`). The public
release should not depend on app passwords.

## 1. Google (Gmail)

### Which scope
- `https://www.googleapis.com/auth/gmail.send` ("Send email on your behalf")
  is a **sensitive** scope. `https://mail.google.com/` ("Read, compose, send,
  and permanently delete all your email") is **restricted**, and so are
  `gmail.compose`, `gmail.modify`, `gmail.readonly`.
  <https://developers.google.com/workspace/gmail/api/auth/scopes> (updated
  2026-09-10).
- Sensitive scopes "require additional OAuth App Verification"; restricted
  scopes "require restricted scope OAuth App Verification" and, when
  restricted data is stored on servers or transmitted, "a security
  assessment" (same page).
- The policy page says "an app that only uses Gmail APIs to occasionally send
  emails on a user's behalf shouldn't request the scope that provides full
  access" (<https://developers.google.com/identity/protocols/oauth2/policies>,
  last modified 2026-08-05). So: **`gmail.send`, not `mail.google.com`.**

### Two ways to send with that account
| | Gmail API `messages.send` | SMTP with XOAUTH2 |
|---|---|---|
| Scope | `gmail.send` (sensitive) | `https://mail.google.com/` (restricted) |
| Verification | OAuth app verification | verification **and an annual security assessment**; "your app must show full utilization of `https://mail.google.com/`" |
| Message | RFC 2822 message, base64url in `raw` | the same message over SMTP (`AUTH XOAUTH2`) |
| Max size | NOT CONFIRMED (the pages do not state it) | NOT CONFIRMED (an example banner shows `SIZE 35651584`, not a documented limit) |

Sources: the scopes page above;
<https://developers.google.com/workspace/gmail/api/guides/sending> (updated
2026-09-10);
<https://developers.google.com/workspace/gmail/imap/xoauth2-protocol>
(updated 2026-09-15; it also says "If your app does not require
`https://mail.google.com/`, migrate to the Gmail API and use more granular
restricted scopes"). The proposal is the REST API with `gmail.send`.

### What the verification asks for
From <https://support.google.com/cloud/answer/13461325> (steps),
<https://support.google.com/cloud/answer/13464321> (requirements) and
<https://support.google.com/cloud/answer/7454865> (consent screen):
1. A consent screen configured, the app published to production (apps "in
   development, testing or staging are not applicable for verification").
2. A **homepage** on a domain the owner has verified in Search Console: it
   must describe the app, "can not be only a login page", and link the privacy
   policy.
3. A **privacy policy** at a public URL on the same domain, linked from the
   homepage and from the consent screen (same URL). "You must have a privacy
   policy URL."
4. A **scope justification**, including why a narrower scope would not work.
5. A **demo video** of the whole flow with the OAuth grant, the same app and
   branding, the full consent screen and the exact scopes.
6. The limited-use rules: data only for the user-facing feature, restrictions
   on transfer and human reading.
- Security assessment: "For restricted scopes only"; per these pages
  `gmail.send` does **not** need it.
- Duration: "Depending on the sensitivity of the data being requested,
  verification might require several months" (7454865). A number for sensitive
  scopes: NOT CONFIRMED. **Start early.**

### Testing mode
- External app, publishing status "Testing": "a refresh token expiring in 7
  days" unless only name, email and profile scopes are used
  (<https://developers.google.com/identity/protocols/oauth2>, updated
  2026-10-16). Other reasons for an invalid refresh token: not used for six
  months, password changed when the token has Gmail scopes, more than 100
  refresh tokens per account per client (the oldest is silently invalidated).
- An unverified app with sensitive scopes shows the "unverified app" screen
  and "will be limited to 100 new users until it is verified" (7454865).
- The number of test users in Testing mode: NOT CONFIRMED.
- Personal use: an app is "for personal use" if it is shared with nobody, or
  used by fewer than 100 people known personally to the owner
  (policies page above).
  **Consequence for development**: with Testing mode the user would have to
  sign in again every 7 days, which is why SMTP with an app password is the
  development route.

### Android client and library
- An Android OAuth client is created in the Cloud Console with the **package
  name and the SHA-1 signing certificate fingerprint** ("You will need to
  specify your app's package name and SHA-1 signature";
  <https://developer.android.com/identity/authorization>; also
  <https://support.google.com/cloud/answer/15549257>, which gives the
  `keytool -list -v -keystore ... -alias ...` command and says a production
  key needs its own client ID). With Play App Signing the SHA-1 is the one
  shown in the Play Console. A debug build and a release build are two
  fingerprints, so two client IDs.
- The recommended API: "For authorizing actions that need access to user data
  stored by Google, we recommend using `AuthorizationClient`" (play-services-auth
  `Identity.getAuthorizationClient(activity).authorize(...)`, with
  `AuthorizationRequest.builder().setRequestedScopes(...)`; the result carries
  an `accessToken`). A refresh token needs `requestOfflineAccess(serverClientId)`
  (needs a web client on the server side, i.e. a backend: **we have none**),
  so without a backend the access token is short-lived and the app asks again
  silently each time (the call returns a token without UI when the user has
  already agreed). Page: same as above. This is a point to test in the real
  phase.
- Custom URI schemes "are no longer supported on Android" and loopback is
  "DEPRECATED" for Android (<https://developers.google.com/identity/protocols/oauth2/native-app>);
  PKCE is supported there. So a generic AppAuth flow for Google is not the
  recommended Android route.

## 2. Microsoft (Outlook.com, Hotmail, Live)

- **Registration** in Microsoft Entra: account type "Personal accounts only"
  (`PersonalMicrosoftAccount`) or "Any Entra ID Tenant + Personal Microsoft
  accounts" (`AzureADandPersonalMicrosoftAccount`)
  (<https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app>,
  <https://learn.microsoft.com/en-us/entra/identity-platform/supported-accounts-validation>).
  A workforce or external tenant is needed to register (the default directory
  is enough). Limits for personal-account apps: max two client secrets, no
  app roles, max 30 permissions per resource.
- **Permission:** `Mail.Send` is listed as the least privileged permission for
  "Delegated (personal Microsoft account)" for `sendMail`
  (<https://learn.microsoft.com/en-us/graph/api/user-sendmail>, updated
  2026-06-19). Whether admin consent is needed: NOT CONFIRMED (the permissions
  reference was too large to read in full); for a personal account there is no
  admin, the user consents.
- **Android redirect URI:** `msauth://<PACKAGE_NAME>/<BASE64_URL_ENCODED_PACKAGE_SIGNATURE>`
  and a matching intent filter in the manifest
  (<https://learn.microsoft.com/en-us/entra/msal/android/>, updated
  2026-01-28). The hash algorithm of the signature: NOT CONFIRMED on the pages
  read. MSAL Android: Min SDK 16+, Target SDK 33+. The endpoint for personal
  accounts only is `https://login.microsoftonline.com/consumers`
  (<https://learn.microsoft.com/en-us/entra/msal/android/msal-configuration>).
- **sendMail limits:** the JSON form can "include a file attachment in the
  same sendMail action call"; the page states **no** size limit and says
  delivery is "subject to Exchange Online limitations" (user-sendmail page).
  The 3 MB threshold lives on
  <https://learn.microsoft.com/en-us/graph/outlook-large-attachments>: under
  3 MB one POST to `attachments`; 3 MB to 150 MB needs an **upload session**
  on an existing message (a draft), which needs `Mail.ReadWrite`, and every
  PUT range "less than 4 MB". Whether the 3 MB rule applies inside
  `sendMail` JSON: NOT CONFIRMED. For our PDFs (often below 3 MB, up to 14 MB
  by the app's limit) the plan is: small PDF -> `sendMail` with the attachment,
  large PDF -> create a draft, upload session, then send the draft (the send
  endpoint page was not read: NOT CONFIRMED).
- **Consent label:** "Apps that are registered by using a Microsoft account
  can't be publisher verified"; publisher verification needs a Partner account
  and a work or school tenant
  (<https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview>).
  Whether a personal-accounts-only app shows an "unverified" label: NOT
  CONFIRMED.
- **Tokens:** auth code flow with PKCE; "Refresh tokens for web apps and
  native apps don't have specified lifetimes"; the refresh token is returned
  only with `offline_access` (<https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow>).
  Personal-account lifetime: NOT CONFIRMED.
- **Library:** MSAL Android is the Microsoft library for Android
  (<https://learn.microsoft.com/en-us/entra/identity-platform/reference-v2-libraries>);
  Flutter packages and AppAuth are not listed there (official status NOT
  CONFIRMED), and the page says another library is fine if it has a certified
  OpenID Connect implementation.
- **SMTP for comparison:** SMTP AUTH with XOAUTH2 and the scope
  `https://outlook.office.com/SMTP.Send`, "available for both Microsoft 365 ...
  and Outlook.com users"
  (<https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth>,
  updated 2025-10-17). This is the closest to what the app does today (the
  same `mailer` SMTP code with an access token instead of a password:
  `SmtpServer(xoauth2Token:)`), and a candidate that avoids the Graph size
  rules. Graph `sendMail` is the other candidate.

## 3. Yahoo

- <https://developer.yahoo.com/oauth2/guide/> says "OAuth 2.0 is currently
  supported by Oath Ad Platforms and UserInfo APIs." There is **no** mail API,
  no SMTP XOAUTH2 and no mail scope on the official pages read
  (<https://developer.yahoo.com/oauth2/guide/faq/> has nothing about mail
  either). **NOT CONFIRMED** that Yahoo offers OAuth for third-party sending,
  so for Yahoo the app password (SMTP) and the share route stay the only
  routes until Yahoo says otherwise.

## 4. How the sign-in screen opens, and the libraries

| Option | Google | Microsoft | Notes |
|---|---|---|---|
| Native account chooser | `AuthorizationClient` (Google Play services): the Google sheet, no browser | MSAL Android (system browser or broker) | Best UX, official, needs a small Kotlin layer behind a channel (like `ScanFilesHandler`) |
| AppAuth (system browser, Custom Tabs, PKCE) | Not the recommended route on Android (custom schemes unsupported) | Works with a custom scheme (`msauth://`) | One generic library for any OpenID provider, e.g. a future provider |
| A Flutter wrapper package | exists, not evaluated | exists, not evaluated | adds a dependency; the licence, maintenance and the Kotlin it pulls in need a review first |

**Proposal:** one Dart port (`MailSender`, already there) with two new
implementations: `GmailApiMailSender` (token from `AuthorizationClient`) and
`OutlookMailSender` (token from MSAL, SMTP XOAUTH2 or Graph), each with a thin
Kotlin class behind a method channel that returns only an access token (the
Dart side never sees a client secret; there is none for Android clients).
Yahoo stays on SMTP. The user then picks the provider, the provider's own
sign-in opens at once, and Settings shows "Connected as ..." with a
"Disconnect" button (revoke and delete tokens).

**Tokens:** the same `MailCredentialStore` (Android Keystore through
`flutter_secure_storage`, outside backups); refresh tokens (Microsoft) are
stored there, access tokens are kept in memory; sign-out deletes both. No token
in logs, ever (the canary test of Phase 4 extends to them).

## 5. Check list for the user (what the project needs before the code)

1. **The final package id.** Today it is the temporary `com.example.one_click_scan`.
   Google's Android client and Microsoft's redirect URI are bound to the
   package name and to the signing key, so the id must be fixed **before** the
   registration (changing it later means new clients and, for Google, a new
   verification).
2. **A release signing key** (and Play App Signing, if the app goes to Google
   Play). The SHA-1 of the debug key, of the upload key and of the Play
   signing key are three different fingerprints; each needs its client.
3. **A Google Cloud project** (consent screen, Android client for debug and
   release, `gmail.send`, test users while in Testing mode).
4. **A Microsoft Entra tenant and app registration** (personal accounts
   supported, the `msauth://` redirect with the release signature, `Mail.Send`,
   `offline_access`).
5. **A public privacy policy URL**, on the domain of the app's homepage, that
   says in plain words that the app runs no server, that the scan goes from the
   user's phone to the user's mail provider and nowhere else, and what the app
   keeps on the phone.
6. **A homepage** on a domain the owner has verified in Search Console
   (describes the app, links the policy, is not only a login page).
7. **A demo video** and the **scope justification** for `gmail.send`.
8. **A decision on Microsoft:** Graph `sendMail` or SMTP XOAUTH2.
9. **Time:** the Google review can take months, so items 1 to 7 should start
   long before the code.

## 6. Where it belongs in the roadmap

Proposed name: **Phase 8: Mail OAuth and public release readiness**, a
milestone that must be **done before any public release**. It comes after the
one-click flow (Phase 5) because SMTP with an app password is enough for the
development of Phase 5 to 7, but its long-lead items (package id, signing key,
privacy policy, Google verification) are not code and should be started in
parallel from now on. `ROADMAP.md` carries this milestone.


---

# Update 2026-10-27: what the app and the process need (Phase 8 work breakdown)

Added while Phase 5 was built. Same rule as above: "NOT CONFIRMED" means looked
for and not found on an official page.

## 7. New facts from the official pages (2026-10-27)
- **Verification time for a sensitive scope.** The Google Cloud FAQ
  (<https://support.google.com/cloud/answer/13463817>) lists sensitive scope
  verification separately from restricted, with an expected time of **10 business
  days**. This is better than the "several months" of section 1 (that page speaks of
  the data requested in general). Both numbers are Google's; plan for the longer one.
- **No security assessment for a sensitive scope only**
  (<https://support.google.com/cloud/answer/13807380>).
- **SMTP.** The same FAQ says that to continue verification an app has to move off
  SMTP and use the sensitive scope `gmail.send`. This confirms the proposal of
  section 1: Gmail API, not SMTP XOAUTH2.
- **Using a scope before approval** gives the "unverified app" screen and the
  100 user limit (Gmail scopes page, <https://developers.google.com/workspace/gmail/api/auth/scopes>).
- **Android client:** package name and SHA-1 per client, and a new client for
  production (<https://developer.android.com/identity/authorization>; the page found
  in this search was old, so re-read it when Phase 8 starts).

## 8. What the app needs (code)
1. **Auth kind in the domain.** `MailAuth` is already sealed with `AppPasswordAuth`.
   Add `OAuthAuth` (provider, account, a way to get an access token), and
   `MailAuthKind.oauth` is already listed in `MailProvider.authKinds`.
2. **A token source behind a port** (`domain/ports/oauth_token_source.dart`):
   `signIn(provider)`, `accessToken(account)` (silent), `signOut(account)`. Two Kotlin
   classes behind the existing style of method channel: Google `AuthorizationClient`,
   Microsoft MSAL. The Dart side only ever sees an access token.
3. **Two new `MailSender`s:** `GmailApiMailSender` (REST `messages.send`, MIME as
   base64url `raw`; the size limit is NOT CONFIRMED) and `OutlookMailSender` (Graph
   `sendMail`, or SMTP XOAUTH2 with the existing `mailer` code). The registry
   chooses the sender by `MailProvider` and the stored auth kind; `SendScanPdf`
   changes only where it builds the auth.
4. **Credential store.** `StoredMailSecret` holds a password today. It needs a
   second shape: the account and, for Microsoft, a refresh token (Keystore, outside
   backups, like ADR-021). Access tokens in memory only. A canary test for tokens.
5. **Outcomes.** New `MailOutcome` cases are probably not needed: "sign-in needed
   again" is `MailAuthFailed`. A distinct `MailNeedsSignIn` lets the screen show a
   "Sign in again" button instead of the app password guide (decide in Phase 8).
6. **Settings screen.** Provider chosen -> its own sign-in opens; then "Connected as
   ..." and a **Disconnect** (revoke the token, delete it). The app password field
   stays for Yahoo and as a fallback. The wizard gets no password field (as today).
7. **Android manifest.** Google needs nothing for `AuthorizationClient`. MSAL needs
   an intent filter for the `msauth://<package>/<signature>` redirect and the
   `<queries>` for the browser. The `INTERNET` permission is already there.
   `network_security_config` is not needed (HTTPS only).
8. **Dependencies.** `play-services-auth` and `com.microsoft.identity.client:msal`
   (Gradle, not Dart packages). Each needs a licence review for
   `THIRD_PARTY_NOTICES.md` and a size check (the APK is 122 MB now).
9. **`no_network_test`.** It allows the network only in `services/mail/`. The OAuth
   token classes are a second place that talks to the network (Google and
   Microsoft); the test needs a named exception, written down in an ADR.
10. **Tests without real accounts:** fake token source, a local test server that
    speaks the Gmail and Graph request shapes (like `tool/smtp_test_server.dart`).
    A real Google or Microsoft account is not used in automatic tests; the real
    sign-in is a check by the user on a phone.
11. **Phase 5 is not affected.** The flow works with `MailSender` and
    `MailAuth`; One Click, preview, Discard and the manual retry do not change when
    OAuth arrives.

## 9. What the process needs (not code), in the order that unblocks the rest
1. **Final package id and the signing keys** (debug, upload, Play signing). Every
   client below is bound to them. The id is still `com.example.one_click_scan`.
2. **A public domain** with a homepage and a **privacy policy** (the app runs no
   server; the scan goes from the phone to the user's provider only).
3. **Google Cloud project:** consent screen (External), scope `gmail.send`, Android
   clients for each SHA-1, test users while in Testing (refresh token of 7 days).
4. **Microsoft Entra registration:** personal accounts supported, `Mail.Send` and
   `offline_access`, the `msauth://` redirect with the release signature.
5. **Google verification:** scope justification, demo video of the whole flow,
   published app. Start before the code (item 1 to 3 first).
6. **Decision needed from the user:** Microsoft by Graph `sendMail` (3 MB rule for
   attachments, upload session above it) or by SMTP XOAUTH2 (reuses the `mailer`
   code, no size rule beyond the server's).
7. **Yahoo:** stays on app password and the share route (no OAuth for mail
   confirmed).
8. **Decision needed from the user:** whether the first public release waits for
   the Google verification, or ships with the app password and the share route.
