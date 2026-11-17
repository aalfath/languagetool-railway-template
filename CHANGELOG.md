# Changelog

Breaking changes are listed first in each entry.

## 6.8 (2026-11-17)

- First release of this template: LanguageTool `6.8` (`erikvl87/languagetool:6.8@sha256:ef8fa12cbd485166c9ceeb7139d76d56d07707a624da6bb1fc1fbb5411750527`, built from the upstream `v6.8` tag).
- One service built from this repo: the LanguageTool HTTP API on `PORT` (8010), health check `/v2/languages`, Railway volume at `/ngrams`.
- Optional `LT_NGRAM_LANGUAGES` downloads LanguageTool's official n-gram data (en, de, es, fr, nl) onto the volume once.
- N-gram data is unpacked with the JDK's jar tool (the en set uses ZIP64, which BusyBox unzip can't stream). N-grams switch on only once both en and de are present (LanguageTool 6.8 drops English and German spell checking otherwise).
- Safe defaults for a public API: 120 requests per client per minute (client IP from `X-Forwarded-For`), 50,000 characters per check, 60 s per check, Java heap capped at 2 GB.
