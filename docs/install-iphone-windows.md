# Install on an iPhone using Windows — no paid developer membership

Requirements: an iPhone running iOS 15 or later, a Windows computer, a USB cable, and your own
Apple account. Study Trainer is free and open source. This installation method uses AltStore
Classic and Apple's free personal signing. It needs renewal every seven days; it is not a
permanently signed App Store or TestFlight installation.

## 1. Install AltStore Classic once

Follow the [official Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).
They provide the current AltServer installer and the required Apple iTunes/iCloud downloads.
The guide recommends Apple's direct installers; it links a separate workaround for Microsoft
Store iCloud installations. Use **AltStore Classic**, which supports signing your own apps.

In brief: install the prerequisites and AltServer on Windows, connect and unlock the iPhone,
trust the computer, enable Wi-Fi sync in iTunes, and use AltServer's tray icon → Install AltStore
→ your iPhone. Complete Apple-account authentication locally in AltServer. On the iPhone, trust
the developer under Settings → General → VPN & Device Management (the label varies by iOS).
On iOS 16+, follow the guide to enable Developer Mode under Privacy & Security and restart if asked.
Never send your Apple password, two-factor code or signing certificates to the assistant.

## 2. Install Study Trainer

Download the [tested iPhone preview](https://github.com/siirty/lichess-study-trainer/releases/tag/ios-preview-v0.1.0).
Its IPA is a compiled arm64 iPhone application for iOS 15+, intentionally unsigned: AltStore
signs it with your own account and installs it for your device. Downloading it in Safari alone
does not install it.

Keep AltServer running and the iPhone connected by USB or reachable on the same private network.
On the iPhone, [add the Study Trainer source to AltStore Classic](altstore://source?url=https://raw.githubusercontent.com/siirty/lichess-study-trainer/main/altstore-source.json),
then select Study Trainer → FREE. If the link does not open AltStore, copy this source URL into
AltStore Classic's Sources interface:

```text
https://raw.githubusercontent.com/siirty/lichess-study-trainer/main/altstore-source.json
```

Alternatively, download [study-trainer-ios-unsigned.ipa](https://github.com/siirty/lichess-study-trainer/releases/download/ios-preview-v0.1.0/study-trainer-ios-unsigned.ipa)
to Files on the iPhone, then use My Apps → + in AltStore Classic to select it.
Complete signing prompts on your own devices. This preview's device release build and native
iPhone simulator flow passed [macOS CI](https://github.com/siirty/lichess-study-trainer/actions/runs/42635436689).
Installation on your particular iPhone, live Lichess login and platform file-picker dialogs
still require local verification.

## 3. Start training

Open Study Trainer → Import. Paste a public Lichess study URL, or choose a stable local source ID
and paste/open PGN. A single import keeps both sides. In Library choose White or Black, then
start due reviews or expand a study/chapter to practice it. Play a repertoire move and save the
review. Hints/mistakes are recorded; restarting does not turn them into a clean recall.

For private studies, Settings → Connect to Lichess uses the system browser and only study:read
permission. This Lichess connection is separate from Apple signing. Review progress and downloaded
studies stay local and remain available offline while the installation's signing is valid.

## 4. Keep it usable

Open AltStore Classic → My Apps → Refresh All before the seven-day signing period expires.
AltServer must be reachable for refresh; background refresh can help, but verify the remaining
days yourself. This Apple signing requirement is separate from offline chess training.
Apple's free route allows three installed sideloaded apps per device, including AltStore itself.
Study Trainer has no app extensions and occupies one additional app slot.

Use Settings → Export full backup periodically, especially before uninstalling, changing the
Apple account used for signing, or switching installation methods. Refresh/update using the
same account and app identity; uninstalling can remove the iPhone's local application data.

Sources checked for this setup:

- [Apple: membership comparison and Personal Team limits](https://developer.apple.com/support/compare-memberships/)
- [AltStore: Windows installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore: My Apps and seven-day renewal](https://faq.altstore.io/altstore-classic/your-altstore)
- [AltStore: free distribution of compiled IPAs](https://faq.altstore.io/developers/distribute-with-altstore-classic)
