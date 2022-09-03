FROM debian:11 AS builder
ARG OPENLDAP_VERSION=2.6.3
ENV OPENLDAP_VERSION=$OPENLDAP_VERSION
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y acl ca-certificates curl gzip libc6 libcom-err2 \
    libcrypt1 libgssapi-krb5-2 libk5crypto3 libkeyutils1 libkrb5-3 \
    libkrb5support0 libltdl7 libnsl2 libnss3-tools libodbc1 libperl5.32 \
    libsasl2-2 libssl1.1 libtirpc3 libwrap0 mdbtools procps psmisc libssl-dev \
    libsodium-dev libltdl-dev libsasl2-dev libevent-dev libwrap0-dev \
    build-essential groff-base && \
    mkdir /src
ADD https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz /src/
ADD https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz.asc /src/
RUN cd src && \
    gpg --keyserver keyserver.ubuntu.com  --recv 7F67D5FD1CE1CBCE && \
    gpg --verify openldap-${OPENLDAP_VERSION}.tgz.asc && \
    tar xf openldap-${OPENLDAP_VERSION}.tgz -C /src --strip 1 && \
    rm openldap-${OPENLDAP_VERSION}.tgz && \
    cd /src && \
    ./configure --enable-wrappers --enable-crypt --enable-spasswd \
    --enable-modules --enable-argon2 --enable-overlays
RUN cd src && make depend
RUN cd src && make
RUN cd src && make test


FROM debian:11
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y gzip ca-certificates libcom-err2 \
    libcrypt1 libgssapi-krb5-2 libk5crypto3 libkeyutils1 libkrb5-3 \
    libkrb5support0 libltdl7 libnsl2 libnss3-tools libodbc1 libperl5.32 \
    libsasl2-2 libssl1.1 libtirpc3 libwrap0 mdbtools procps psmisc \
    libssl1.1 libwrap0 libsodium23
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/libexec /usr/local/libexec
COPY --from=builder /usr/local/sbin /usr/local/sbin
COPY --from=builder /usr/local/etc /usr/local/etc
COPY entrypoint.sh /
COPY dhparam /usr/local/etc/openldap/
RUN chmod +x entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
EXPOSE 389 636
