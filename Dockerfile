# FTB Skies 2: Aero – dedicated server (Minecraft 1.21.1 / NeoForge)
# The modpack is installed into /data on the first container start.

FROM eclipse-temurin:21-jre-noble

# Pack ID from the FTB API and the version ID used to download the FTB server
# installer (the installer itself can install every version of the pack)
ARG FTB_PACK_ID=134
ARG INSTALLER_VERSION_ID=100527

LABEL org.opencontainers.image.title="FTB Skies 2: Aero Server" \
      org.opencontainers.image.description="Minecraft server for the FTB Skies 2: Aero modpack" \
      org.opencontainers.image.url="https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero" \
      org.opencontainers.image.source="https://github.com/JonaxScript/ftb-skies-2-aero-docker"

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq \
 && rm -rf /var/lib/apt/lists/*

# Official FTB server installer (can also install other versions via -pack/-version)
RUN curl -fsSL -o /usr/local/bin/ftb-serverinstall \
      "https://api.feed-the-beast.com/v1/modpacks/public/modpack/${FTB_PACK_ID}/${INSTALLER_VERSION_ID}/server/linux" \
 && chmod 755 /usr/local/bin/ftb-serverinstall

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Strip CRLF in case the file was edited on Windows
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
 && chmod 755 /usr/local/bin/entrypoint.sh

ENV FTB_PACK_ID=${FTB_PACK_ID} \
    FTB_VERSION_ID="" \
    EULA=false \
    JVM_OPTS="-Xms6G -Xmx8G" \
    OPS="" \
    MOTD="FTB Skies 2: Aero" \
    LEVEL=world \
    PUID=99 \
    PGID=100

WORKDIR /data
VOLUME /data
EXPOSE 25565/tcp

# Starting the modpack takes several minutes, the first install even longer
HEALTHCHECK --start-period=20m --interval=1m --timeout=10s --retries=3 \
    CMD bash -c '</dev/tcp/127.0.0.1/25565' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
