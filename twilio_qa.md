# Voice as Twilio SMS Capability — QA Test Cases
## Prerequisites

* Enterprise edition
* `channel_voice` feature flag enabled: `Account.find(<id>).enable_features('channel_voice'); Account.find(<id>).save!`
* Twilio account with a voice-capable phone number
* Twilio API Key SID + API Key Secret

---

## Voice inbox creation

1. ~~Create Voice inbox via Voice tile with valid credentials — Channel created with voice_enabled: true, twiml_app_sid auto-provisioned, SMS and calls work~~
2. ~~Create Voice inbox with a number that doesn't support voice (e.g., short code) — Fails with "This phone number does not support voice calls" error~~
3. ~~Create Voice inbox with invalid Twilio credentials — Fails with clear error message~~

## Enable voice on existing SMS inbox

 5. ~~SMS inbox (phone number, no ~~`~~api_key_sid~~`~~) → enable voice — Prompts for both ~~`~~api_key_sid~~`~~ and ~~`~~api_key_secret~~`~~, provisions TwiML app~~
 6. ~~SMS inbox (phone number, has ~~`~~api_key_sid~~`~~, no ~~`~~api_key_secret~~`~~) → enable voice — Prompts for ~~`~~api_key_secret~~`~~ only, provisions TwiML app~~
 7. ~~SMS inbox (phone number, has api_key_sid + api_key_secret) → enable voice — No credential fields, just toggle and update~~
 8. ~~SMS inbox (messaging_service_sid only) — Voice tab not shown (voice requires phone number)~~
 9. ~~Twilio WhatsApp inbox — Voice tab not shown (~~`~~medium !== 'sms'~~`~~)~~
10. ~~SMS inbox without ~~`~~channel_voice~~`~~ feature flag — Voice tab not shown~~
11. ~~Enable voice via API when ~~`~~channel_voice~~`~~ flag is off — Voice fields silently ignored~~

## Disable voice

12. ~~SMS+Voice channel → disable voice — TwiML app deleted from Twilio, ~~`~~twiml_app_sid~~`~~ cleared, ~~`~~api_key_sid~~`~~ and ~~`~~api_key_secret~~`~~ preserved, SMS still works~~
13. ~~Disable voice when Twilio API fails (e.g., TwiML app already deleted) — Local cleanup still happens, no error shown to user~~

## Re-enable voice

14. ~~Previously disabled voice channel (has api_key_sid + api_key_secret) → re-enable — No credentials needed, new TwiML app provisioned~~
15. ~~Previously disabled voice channel (has api_key_sid, api_key_secret is nil) → re-enable — Prompts for api_key_secret~~

## Voice settings tab UI

16. ~~Voice enabled + configured — Shows toggle (on) + voice webhook URLs~~
17. ~~Voice disabled + credentials exist — Shows toggle (off) only, no credential fields~~
18. ~~Voice disabled + no credentials → toggle on — Shows credential fields when toggled on~~
19. ~~Click Update button — Shows spinner while saving~~
20. ~~After update completes — Tab stays selected (doesn't jump to another tab)~~
21. ~~Voice-enabled inbox still shows Business Hours, CSAT, Help Center, and Configuration tabs~~

## Inbox list and naming

22. ~~Voice-enabled TwilioSms inbox in inbox list — Shows "Voice" as channel name~~
23. ~~Voice-disabled TwilioSms inbox in inbox list — Shows "Twilio SMS" as channel name~~
24. ~~Voice-enabled inbox icon — Shows voice icon (phone)~~

## Inbox creation UI

25. ~~Voice tile shows "Coming Soon" when ~~`~~channel_voice~~`~~ feature flag is off~~
26. ~~Voice tile is clickable when ~~`~~channel_voice~~`~~ feature flag is on~~
27. ~~Voice tile description reads "Handle voice calls and SMS with Twilio"~~
