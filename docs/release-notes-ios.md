Study Trainer 0.1.1: security hardening for the offline Lichess study trainer.

This update bounds local files and network responses, validates backups before replacement,
warns before exporting readable private study data, hides raw exception details, and hardens CI.
See the [security-pass report](https://github.com/siirty/lichess-study-trainer/blob/main/docs/security-pass.md).

Install with **Windows + AltStore Classic + a free Apple account**, on iOS 15 or later.
AltStore signs this unsigned device IPA locally. Renew free signing every seven days through
AltServer. Downloading the IPA alone does not install it.

[Windows installation guide](https://github.com/siirty/lichess-study-trainer/blob/main/docs/install-iphone-windows.md)

After installing AltStore Classic, add this source and choose Study Trainer → FREE / Update:

```text
https://raw.githubusercontent.com/siirty/lichess-study-trainer/main/altstore-source.json
```

Or download the IPA to Files and select it in AltStore Classic → My Apps → +. Update with the same
Apple account and app identity. Export a training backup before changing installation methods;
uninstalling can remove local data. Enter Apple credentials only on your own devices.

Independent GPL engineering preview; not affiliated with Lichess. Private-study OAuth and the
signed installation still require physical-iPhone verification. Backups remain unencrypted.
