# Debian 13 for glibc 2.41: GE-Proton 11 needs 2.38, and Enshrouded 1.0 needs GE-Proton 11.
# Its Steamworks SDK asks for SteamUtils011, which no GE-Proton 10 release provides (checked
# 10-34): the server logs "Version Mismatch / No SteamUtils011" and exits.
FROM debian:13-slim

LABEL org.opencontainers.image.authors="nodiaque-github@abinemail.com"
LABEL org.opencontainers.image.source="https://github.com/CptSandwich/docker-steamcmd-server"

ENV HOME="/serverdata"
# From 11.x GE names the download and its folder with the arch; the start script finds Proton
# at compatibilitytools.d/GE-Proton${GE_PROTON_VERSION}.
ENV GE_PROTON_RELEASE="11-9"
ENV GE_PROTON_VERSION="${GE_PROTON_RELEASE}-x86_64"
ENV GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${GE_PROTON_RELEASE}/GE-Proton${GE_PROTON_VERSION}.tar.gz"
ENV DATA_DIR="/serverdata"
ENV GAME_ID="2278520"
ENV GAME_PARAMS=""
ENV STEAMCMD_DIR="${DATA_DIR}/steamcmd"
ENV SERVER_DIR="${DATA_DIR}/serverfiles"
ENV ASTEAM_PATH="${DATA_DIR}/Steam"
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH="${ASTEAM_PATH}"
ENV STEAM_COMPAT_DATA_PATH="${ASTEAM_PATH}/steamapps/compatdata/${GAME_ID}"
ENV ENSHROUDED_CONFIG="${SERVER_DIR}/enshrouded_server.json"
ENV SERVER_NAME="Enshrouded Docker"
ENV QUERY_PORT="15637"
ENV SERVER_SLOTS="16"
ENV ULWGL_ID=0
ENV BACKUP="false"
ENV BACKUP_INTERVAL=120
ENV BACKUPS_TO_KEEP=12
ENV VALIDATE=""
ENV UMASK=000
ENV UID=99
ENV GID=100
ENV USERNAME=""
ENV PASSWRD=""
ENV USER="steam"
ENV DATA_PERM=770

RUN useradd -d $DATA_DIR -s /bin/bash -g $GID -u $UID $USER && \ 
    sed -i 's#^Components: .*#Components: main non-free contrib#g' /etc/apt/sources.list.d/debian.sources \
    && echo steam steam/question select "I AGREE" | debconf-set-selections \
    && echo steam steam/license note '' | debconf-set-selections \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        procps \
        ca-certificates \
        winbind \
        dbus \
        libfreetype6 \
        libvulkan1 \
        python3 \
        curl \
        wget \
        jq \
        locales \
        lib32gcc-s1 \
    && echo 'LANG="en_US.UTF-8"' > /etc/default/locale \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && rm -f /etc/machine-id \
    && dbus-uuidgen --ensure=/etc/machine-id \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && apt-get autoremove -y

RUN  echo "* hard nice -20" | tee -a /etc/security/limits.conf 

RUN mkdir $DATA_DIR && \
    chown -R $USER $DATA_DIR

ADD /scripts/ /opt/scripts/
ADD /config/ /opt/config/
RUN chmod -R 770 /opt/scripts/
RUN chmod -R 770 /opt/config/
RUN chown -R $USER /opt/config/

RUN mkdir $STEAMCMD_DIR && \
    mkdir $SERVER_DIR

# Fail the build rather than publish an image the 1.0 server cannot start in. Proton itself is
# installed by the start script into the data volume (anything put in /serverdata here is
# hidden by the mount), so this only unpacks the files it checks.
RUN mkdir /tmp/proton-check && \
    wget -q "$GE_PROTON_URL" -O - | tar -xz -C /tmp/proton-check --wildcards \
        "GE-Proton${GE_PROTON_VERSION}/proton" '*/x86_64-unix/lsteamclient.so' '*/x86_64-unix/ntdll.so' && \
    if ! grep -q SteamUtils011 /tmp/proton-check/*/files/lib/wine/x86_64-unix/lsteamclient.so; then \
        echo "GE-Proton ${GE_PROTON_RELEASE} lacks SteamUtils011"; exit 1; fi && \
    need=$(grep -ao 'GLIBC_2\.[0-9]*' /tmp/proton-check/*/files/lib/wine/x86_64-unix/ntdll.so | sed 's/GLIBC_//' | sort -V | tail -1) && \
    have=$(getconf GNU_LIBC_VERSION | awk '{print $2}') && \
    echo "glibc: Proton needs ${need}, image has ${have}" && \
    dpkg --compare-versions "$have" ge "$need" && \
    test -e /usr/lib/x86_64-linux-gnu/libvulkan.so.1 && \
    head -1 "/tmp/proton-check/GE-Proton${GE_PROTON_VERSION}/proton" | grep -q python3 && command -v python3 && \
    rm -rf /tmp/proton-check

#Server Start
ENTRYPOINT ["/opt/scripts/start.sh"]
