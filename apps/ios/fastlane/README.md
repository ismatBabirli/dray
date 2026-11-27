# App Store listing

`metadata/` is the listing for "Wain: AI Coding Agents" (Apple ID 6839484995), in the layout `fastlane deliver` reads. Nothing uploads it yet; paste it into App Store Connect, or upload it with the "Wain CI" API key the release uses.

Limits: name and subtitle 30 characters, promotional text 170, keywords 100, description 4000. Keywords skip the words already in the name, and name no other app or trademark. Other agents are named only in the description, as what Wain works with.

`review_information/notes.txt` holds `DEMO_ADDRESS` and `DEMO_CODE` until a demo machine exists for App Review.

## Answers that live only in App Store Connect

- **App Privacy: Data Not Collected.** No analytics, no account. The push token goes to wainhq.com once, which seals it into a handle and keeps nothing; the handle lives on the user's own machines. Alert text passes straight through to Apple. Dictation runs on the phone or on the user's own Mac. The one judgment call: the relay keeps a per-phone alert count under a one-way hash of the token for about a day, to rate-limit.
- **Age rating: 4+.** Every content question is None. No user-to-user messaging, no web browsing, no ads. The app shows text the user's own coding agents write.
- **Category:** Developer Tools (`metadata/primary_category.txt`).
- **Price:** free, every country.
- **Export compliance:** HTTPS and standard crypto only, already declared by `ITSAppUsesNonExemptEncryption = NO`.
- **Screenshots:** 6.9" iPhone (1320 × 2868) and 13" iPad (2064 × 2752), since the app runs on iPad.
