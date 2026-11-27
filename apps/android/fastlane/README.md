# Google Play listing

`metadata/android/en-US/` is the listing for "Wain: AI Coding Agents" (`com.plorigo.wain`), in the layout `fastlane supply` reads. Nothing uploads it yet; paste it into Play Console, or upload it with the `PLAY_SERVICE_ACCOUNT` key the release uses.

Limits: title 30 characters, short description 80, full description 4000.

## Answers that live only in Play Console

- **Data safety.** Collected: Device or other IDs (Firebase's installation ID and the FCM token), for App functionality, required, encrypted in transit, not shared, no deletion request (Google holds it). Nothing else: no analytics, no account, and what the app sends to the user's own machines is not collected by us. Alert text passes straight through wainhq.com to Firebase.
- **Content rating (IARC):** Utility. No violence, no user-to-user interaction, no location sharing, no purchases.
- **Target audience:** 18 and over. Not designed for children.
- **Ads:** none.
- **App access:** some features need a paired machine; give the demo machine's address and code, as in `apps/ios/fastlane/metadata/review_information/notes.txt`.
- **Privacy policy:** https://www.wainhq.com/docs/reference/privacy
- **Graphics:** 512 × 512 icon, 1024 × 500 feature graphic, phone screenshots at 1080 × 1920 or larger.
