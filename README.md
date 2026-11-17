# LanguageTool on Railway

A Railway template for the [LanguageTool](https://github.com/languagetool-org/languagetool) HTTP server: open-source grammar, style and spell checking for more than 25 languages, behind your own API URL. Point the LanguageTool browser add-on, LibreOffice, Obsidian or your own code at it, and your text never leaves your server.

## What it deploys

| Service | Source | Notes |
|---|---|---|
| **LanguageTool** | this repo (`Dockerfile`) | LanguageTool `6.8` on `erikvl87/languagetool:6.8`, pinned by digest. HTTP API on `PORT` (8010) with a public domain. Health check `/v2/languages`. Volume at `/ngrams`. |

LanguageTool publishes no container image of its own (and no release ZIP since 6.6), so the base is [erikvl87/languagetool](https://github.com/Erikvl87/docker-languagetool), the widely used community image built from the upstream release tag. It already includes fastText for automatic language detection.

The wrapper (`railway-start.sh`) listens on `PORT`, caps the Java heap (Railway shows the JVM the whole host's memory), and writes a server config with safe defaults for a public API:

| Setting | Value |
|---|---|
| Rate limit | 120 requests per client per minute (client IP from Railway's `X-Forwarded-For`) |
| Longest text per check | 50,000 characters |
| Longest time per check | 60 s |
| Java heap | 256 MB start, 2 GB max |
| CORS | open (`*`), so browser add-ins can call it |

## Variables

| Variable | Default | Why |
|---|---|---|
| `PORT` | `8010` | Port Railway routes the public domain to. |

No prompts. Optional variables you can add to the service later:

- `LT_NGRAM_LANGUAGES`: comma-separated list (`en`, `de`, `es`, `fr`, `nl`) of LanguageTool's official [n-gram data sets](https://languagetool.org/download/ngram-data/) to download onto the volume. They catch confused words such as *their/there*. Unpacked sizes: en 15.4 GB, fr 3.4 GB, de 3.3 GB, es 3.3 GB, nl 2.5 GB, so grow the volume first. The download runs once, in the background, and the API keeps working meanwhile. LanguageTool 6.8 drops its English and German spell checkers when n-grams are on but missing for those languages, so the wrapper turns n-grams on only once both `en` and `de` are on the volume: use `en,de` (plus any others), then restart once the logs say the data is ready.
- `Java_Xmx` / `Java_Xms`: Java heap limits (defaults `2g` / `256m`). One language needs about 700 MB; each extra language in use adds 100–200 MB. Raise `Java_Xmx` for many languages or n-grams.
- `langtool_<key>`: any LanguageTool [server setting](https://languagetool.org/development/api/org/languagetool/server/HTTPServerConfig.html), for example `langtool_requestLimit=0` to switch off the rate limit or `langtool_maxTextLength=100000`. These override the defaults above.

## After deploy

1. Open `https://YOUR-DOMAIN/v2/languages`: it lists the supported languages.
2. Check some text: `curl -d "language=en-US" -d "text=This are a test." https://YOUR-DOMAIN/v2/check`.
3. Point your clients at the server. In the LanguageTool browser add-on: **Settings → Advanced settings → LanguageTool server → Other server** and enter `https://YOUR-DOMAIN/v2`. LibreOffice, Obsidian and other clients take the same URL.

The open-source server has no user accounts: anyone who knows the URL can send text to it, within the rate limit. For private use only, remove the public domain and call it from your other Railway services at `http://${{LanguageTool.RAILWAY_PRIVATE_DOMAIN}}:8010/v2`.

## Updates

The service builds from this repo. When we bump the pinned version on `main`, Railway shows an "update available" notice on your project, and you choose when to apply it. Read [CHANGELOG.md](CHANGELOG.md) first. The n-gram data on the volume is kept.

## Local test

```sh
docker compose -f local-test/compose.yaml up -d --build
curl -d "language=en-US" -d "text=This are a test." http://localhost:42495/v2/check
```

LanguageTool is licensed under the [LGPL-2.1](https://github.com/languagetool-org/languagetool/blob/master/COPYING.txt); the base image under the same licence. This wrapper only adds Railway settings.
