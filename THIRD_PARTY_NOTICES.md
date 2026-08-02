# Third-party notices

TomoRead uses the following text-decoding packages for TXT/Markdown import.
Their license texts are retained by the Flutter/Dart package license bundle and
remain available from the linked upstream repositories.

- `charset` 2.0.1 — Apache License 2.0 —
  <https://github.com/shirne/charset-dart>
- `charset_converter` 2.5.1 — BSD 3-Clause License —
  <https://github.com/pr0gramista/charset_converter>

These packages provide independently licensed codecs. TomoRead does not copy
encoding tables or detector code from the ColorTxt reference checkout.

TomoRead also uses `opencc` 1.1.0, an Apache License 2.0 Dart wrapper around
OpenCC, for phrase-aware Simplified/Traditional Chinese display conversion:
<https://github.com/lindeer/opencc-dart>. OpenCC and its dictionaries are
licensed under Apache License 2.0. Conversion output is a reversible display
projection in TomoRead and never overwrites the imported book.
