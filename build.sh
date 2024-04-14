#!/bin/bash

set -e
set -o pipefail
set -x

NMAP_VERSION=7.80
OPENSSL_VERSION=1.1.0h

# Fix jessie repo
rm -rfv /etc/apt/sources.list
echo "deb http://archive.debian.org/debian-security jessie/updates main" >> /etc/apt/sources.list.d/jessie.list
echo "deb http://archive.debian.org/debian jessie main" >> /etc/apt/sources.list.d/jessie.list


# Install Python and zip
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -yy --force-yes python zip automake

# Create build dir for workflows
mkdir -p /build

function build_openssl() {
    cd /build

    # Download OpenSSL
    curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -k
    tar zxvf openssl-${OPENSSL_VERSION}.tar.gz
    cd openssl-${OPENSSL_VERSION}

    # Configure OpenSSL
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static' ./Configure no-shared no-async linux-x86_64

    # Build
    make
    echo "** Finished building OpenSSL"
}

function build_nmap() {
    cd /build

    # Download Nmap
    curl -LO http://nmap.org/dist/nmap-${NMAP_VERSION}.tar.bz2 -k
    tar xjvf nmap-${NMAP_VERSION}.tar.bz2
    mv nmap-${NMAP_VERSION} nmap
    
    # # Get latest version of Nmap
    # git clone https://github.com/nmap/nmap.git --depth 1
	# cd nmap

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
    echo $?

    ls -la /build/nmap/nmap-*
    /opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-strip nmap ncat/ncat nping/nping
}

function doit() {
    build_openssl
    build_nmap

    # Copy to output
    if [ -d /output ]
    then
        OUT_DIR=/output/`uname | tr 'A-Z' 'a-z'`/`uname -m`
        mkdir -p $OUT_DIR
        cp /build/nmap/nmap $OUT_DIR/
        cp /build/nmap/ncat/ncat $OUT_DIR/

        rm -rfv /build/nmap/nmap-header-template.cc
        cp /build/nmap/nmap-* $OUT_DIR/

        # cp /build/nmap/{nmap-os-db,nmap-payloads,nmap-rpc} $OUT_DIR/

        NMAP_VERSION=$(/build/nmap/nmap | head -n 1 | cut -d " " -f2)
        zip -r "/output/nmap-static-binaries-$NMAP_VERSION.zip" $OUT_DIR

        # Also storing the build files and shit
        zip -r "/output/nmap-build-files-$NMAP_VERSION.zip" "/build/" "/output/"


        echo "** Finished **"
    else
        echo "** /output does not exist **"
    fi
}

doit