# LanguageTool HTTP server for Railway.
# LanguageTool publishes no container image (and no release ZIP since 6.6), so this
# builds on erikvl87/languagetool, the community image built from the upstream
# v6.8 tag (LGPL-2.1), pinned by version and digest.
# Bump the tag and the digest together, and add a CHANGELOG.md entry.
FROM erikvl87/languagetool:6.8@sha256:ef8fa12cbd485166c9ceeb7139d76d56d07707a624da6bb1fc1fbb5411750527

# Start as root only to give the Railway volume (/ngrams) to the languagetool
# user; the start script then drops to that user before it starts Java.
USER root
COPY --chmod=755 railway-start.sh /usr/local/bin/railway-start.sh
RUN install -d -o languagetool -g languagetool /ngrams

ENV PORT=8010
EXPOSE 8010
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
