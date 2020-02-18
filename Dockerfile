FROM ubuntu:18.04

VOLUME /config

ARG DOCKERIZE_ARCH=amd64
ARG DOCKERIZE_VERSION=v0.6.1
ARG DUMBINIT_VERSION=1.2.2

# Required for omitting the tzdata configuration dialog
ENV DEBIAN_FRONTEND=noninteractive

# Update, upgrade and install core software
RUN apt update \
    && apt -y upgrade \
    && apt -y install software-properties-common wget git curl jq \
    && apt update \
    && apt install -y sudo curl rar unrar zip unzip ufw iputils-ping openvpn bc tzdata net-tools dnsutils \
    && apt install -y tinyproxy telnet \
    && wget https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_amd64.deb \
    && dpkg -i dumb-init_${DUMBINIT_VERSION}_amd64.deb \
    && rm -rf dumb-init_${DUMBINIT_VERSION}_amd64.deb \
    && curl -L https://github.com/jwilder/dockerize/releases/download/${DOCKERIZE_VERSION}/dockerize-linux-${DOCKERIZE_ARCH}-${DOCKERIZE_VERSION}.tar.gz | tar -C /usr/local/bin -xzv \
    && apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 
    # && groupmod -g 1000 users \
    # && useradd -u 911 -U -d /config -s /bin/false abc \
    # && usermod -G users abc

RUN useradd -m docker && echo "docker:docker" | chpasswd && adduser docker sudo

ADD vpnchain /etc/vpnchain/
ADD tinyproxy /opt/tinyproxy/

ENV HEALTH_CHECK_HOST=google.com \
    DOCKER_LOG=false

#HEALTHCHECK --interval=5m CMD /etc/scripts/healthcheck.sh

# Expose port and run
EXPOSE 8888
CMD ["dumb-init", "/etc/vpnchain/vpnchain.sh"]
