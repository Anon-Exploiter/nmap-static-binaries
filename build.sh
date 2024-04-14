#!/bin/bash

set -e
set -o pipefail
set -x

NMAP_VERSION=workflow_fills_me
OPENSSL_VERSION=1.1.0h

echo $NMAP_VERSION

# Fix jessie repo
rm -rfv /etc/apt/sources.list
echo "deb http://archive.debian.org/debian-security jessie/updates main" >> /etc/apt/sources.list.d/jessie.list
echo "deb http://archive.debian.org/debian jessie main" >> /etc/apt/sources.list.d/jessie.list

# Install Python and zip
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --force-yes -yy python zip 


function build_openssl() {
    cd /build

    # Download
    curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -k
    tar zxvf openssl-${OPENSSL_VERSION}.tar.gz
    cd openssl-${OPENSSL_VERSION}

    # Configure
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static' ./Configure no-shared no-async linux-x86_64

    # Build
    make
    echo "** Finished building OpenSSL"
}

function build_nmap() {
    cd /build

    # Download
    curl -LO http://nmap.org/dist/nmap-${NMAP_VERSION}.tar.bz2 -k
    tar xjvf nmap-${NMAP_VERSION}.tar.bz2
    cd nmap-${NMAP_VERSION}

    # Configure
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
        CXX='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-g++ -static -static-libstdc++ -fPIC' \
        LD=/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-ld \
        LDFLAGS="-L/build/openssl-${OPENSSL_VERSION}"   \
        CPPFLAGS="-I/build/openssl-${OPENSSL_VERSION}/include" \
        ./configure \
            --without-ndiff \
            --without-zenmap \
            --without-subversion \
            --without-nmap-update \
            --with-pcap=linux \
            --with-openssl=/build/openssl-${OPENSSL_VERSION}

    # Don't build the libpcap.so file
    sed -i -e 's/shared\: /shared\: #/' libpcap/Makefile

    # Build
    make -j4
    /opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-strip nmap ncat/ncat nping/nping
}

function doit() {
    build_openssl
    build_nmap

    DATE_TIME=`date "+%d-%m-%Y_%H-%M-%S"`

    # Copy to output
    if [ -d /output ]
    then
        OUT_DIR=/output/`uname | tr 'A-Z' 'a-z'`/`uname -m`
        mkdir -p $OUT_DIR

        cp /build/nmap-${NMAP_VERSION}/nmap $OUT_DIR/
        cp /build/nmap-${NMAP_VERSION}/ncat/ncat $OUT_DIR/
        cp /build/nmap-${NMAP_VERSION}/{nmap-os-db,nmap-payloads,nmap-rpc} $OUT_DIR/ || true
        cp /build/nmap-${NMAP_VERSION}/nmap-* $OUT_DIR/ || true

        zip -rv "/output/nmap-static-binaries_v${NMAP_VERSION}.zip" $OUT_DIR || true


        # zip -rv "/output/nmap-static-binaries_v${NMAP_VERSION}_${DATE_TIME}.zip" $OUT_DIR || true
        # rm -rfv /build/nmap-${NMAP_VERSION}/nmap-header-template.cc
        # zip -rv "/output/nmap-build-files_v${NMAP_VERSION}_${DATE_TIME}.zip" "/build/" "/output/" || true


        echo "** Finished **"
    else
        echo "** /output does not exist **"
    fi
}

doit