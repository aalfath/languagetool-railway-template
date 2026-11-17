#!/bin/bash
# Railway start script for LanguageTool.
#  - listens on $PORT (default 8010) on all interfaces, CORS open for add-ins
#  - writes a server config with safe defaults for a public API
#  - optional: downloads LanguageTool's n-gram data for the languages in
#    LT_NGRAM_LANGUAGES (for example "en,de") onto the /ngrams volume, once
set -euo pipefail

NGRAM_DIR=/ngrams
CONFIG=/tmp/languagetool-server.properties

if [ "$(id -u)" = "0" ] && [ "${1:-}" != "--as-user" ]; then
  mkdir -p "$NGRAM_DIR"
  chown languagetool:languagetool "$NGRAM_DIR"
  # Keep the environment (-p) and use bash: the account's shell is nologin.
  exec su -p -s /bin/bash languagetool -c 'exec /usr/local/bin/railway-start.sh --as-user'
fi

PORT="${PORT:-8010}"
cd /LanguageTool

# --- server configuration ---------------------------------------------------
# Defaults first; any langtool_<key> variable is appended later and wins
# (same convention as the erikvl87/languagetool image).
{
  cat /LanguageTool/config.properties          # fastText model and binary
  # LanguageTool 6.8 drops the English and German spell checkers when a
  # language model folder is set but holds no data for that language, so the
  # n-grams are switched on only once both en and de are on the volume.
  if [ -d "$NGRAM_DIR/en" ] && [ -d "$NGRAM_DIR/de" ]; then
    echo "languageModel=$NGRAM_DIR"
  fi
  echo "trustXForwardForHeader=true"           # rate limits per client, not per Railway proxy
  echo "requestLimit=120"
  echo "requestLimitPeriodInSeconds=60"
  echo "maxTextLength=50000"
  echo "maxCheckTimeMillis=60000"
  echo "pipelineCaching=true"
  echo "pipelineExpireTimeInSeconds=3600"
  echo "maxPipelinePoolSize=5"
  echo "cacheSize=1000"
  echo "cacheTTLSeconds=300"
  for var in ${!langtool_*}; do
    key="${var#langtool_}"
    case "$key" in
      fasttextModel|fasttextBinary|languageModel) echo "Ignoring $var: the template manages it." >&2 ;;
      *) echo "$key=${!var}" ;;
    esac
  done
} > "$CONFIG"
echo "LanguageTool server config:"
sed 's/^\(.*[Pp]assword=\).*/\1***/' "$CONFIG"

# --- optional n-gram download ------------------------------------------------
# Official data: https://languagetool.org/download/ngram-data/
# Unpacked sizes: en 15.4 GB, fr 3.4 GB, de 3.3 GB, es 3.3 GB, nl 2.5 GB.
ngram_file() {
  case "$1" in
    en) echo "ngrams-en-20150817.zip 15400000" ;;
    de) echo "ngrams-de-20150819.zip 3300000" ;;
    es) echo "ngrams-es-20150915.zip 3300000" ;;
    fr) echo "ngrams-fr-20150913.zip 3450000" ;;
    nl) echo "ngrams-nl-20181229.zip 2550000" ;;
    *) return 1 ;;
  esac
}

download_ngrams() {
  local langs lang spec file need_kb free_kb tmp rc
  langs="$(echo "${LT_NGRAM_LANGUAGES:-}" | tr ',;' '  ' | tr 'A-Z' 'a-z')"
  for lang in $langs; do
    if [ -d "$NGRAM_DIR/$lang" ]; then
      echo "[ngrams] $lang: already on the volume."
      continue
    fi
    if ! spec="$(ngram_file "$lang")"; then
      echo "[ngrams] $lang: no official n-gram data (available: en de es fr nl), skipped."
      continue
    fi
    file="${spec% *}"
    need_kb=$(( ${spec#* } * 105 / 100 ))   # unpacked size + 5 %, in KB
    free_kb="$(df -Pk "$NGRAM_DIR" | awk 'NR==2 {print $4}')"
    if [ "$free_kb" -lt "$need_kb" ]; then
      echo "[ngrams] $lang: needs about $(( need_kb / 1000000 )) GB free on the volume, only $(( free_kb / 1000000 )) GB free. Grow the volume, then restart. Skipped."
      continue
    fi
    tmp="$NGRAM_DIR/.download-$lang"
    rm -rf "$tmp" && mkdir -p "$tmp"
    echo "[ngrams] $lang: downloading and unpacking $file (this takes a while)..."
    set +e
    # Stream straight into unzip so the ZIP itself never needs disk space.
    # unzip stops at the central directory, so curl may end with 23 (write error).
    curl -fsSL --retry 3 "https://languagetool.org/download/ngram-data/$file" | (cd "$tmp" && unzip -q -o -)
    rc=("${PIPESTATUS[@]}")
    set -e
    if [ "${rc[1]}" = "0" ] && { [ "${rc[0]}" = "0" ] || [ "${rc[0]}" = "23" ]; } && [ -d "$tmp/$lang" ]; then
      mv "$tmp/$lang" "$NGRAM_DIR/$lang"
      rm -rf "$tmp"
      echo "[ngrams] $lang: ready. Restart the service once to load it."
    else
      rm -rf "$tmp"
      echo "[ngrams] $lang: download failed (curl ${rc[0]}, unzip ${rc[1]}). It is retried on the next start."
    fi
  done
}

if [ -n "${LT_NGRAM_LANGUAGES:-}" ]; then
  download_ngrams &
fi
if [ -n "$(ls -d "$NGRAM_DIR"/[a-z][a-z] 2>/dev/null)" ] && ! grep -q '^languageModel=' "$CONFIG"; then
  echo "[ngrams] Data found, but n-grams stay off until both en and de are on the volume (LanguageTool drops English and German spell checking otherwise)."
fi

# --- start the server ----------------------------------------------------------
# Railway shows the JVM the host's memory, so the heap is capped explicitly.
# Override with Java_Xms / Java_Xmx (same names as the base image).
# G1 periodic GC hands unused heap back, so an idle server stays small.
exec java \
  "-Xms${Java_Xms:-256m}" "-Xmx${Java_Xmx:-2g}" \
  -XX:+UseG1GC -XX:G1PeriodicGCInterval=60000 \
  -XX:+ExitOnOutOfMemoryError \
  -cp languagetool-server.jar org.languagetool.server.HTTPServer \
  --port "$PORT" --public --allow-origin '*' \
  --config "$CONFIG"
