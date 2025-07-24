FROM harbor.spacemit.com/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

COPY ubuntu.mirror /etc/apt/sources.list.d/ubuntu.sources

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
        tzdata \
        locales \
        repo \
        wget \
        zip \
        build-essential \
        g++ \
        git \
        autoconf \
        automake \
        texinfo \
        bison \
        xxd \
        curl \
        flex \
        gawk \
        gdisk \
        gperf \
        libgmp-dev \
        libmpfr-dev \
        libmpc-dev \
        libz-dev \
        libssl-dev \
        libncurses-dev \
        libtool \
        patchutils \
        python3 \
        screen \
        unzip \
        zlib1g-dev \
        libyaml-dev \
        cpio \
        bc \
        dosfstools \
        mtools \
        device-tree-compiler \
        libglib2.0-dev \
        libpixman-1-dev \
        kpartx \
        rsync \
        swig \
        u-boot-tools \
        g++-multilib \
        busybox-static \
        python3-dev \
        python3-setuptools \
        python3-yaml \
        expect \
        libconfuse2 \
        uuid-runtime \
        vim \
        net-tools \
        inetutils-ping \
        dnsutils \
        telnet \
        pigz \
        jq \
        cppcheck \
        devscripts \
        python3-aiohttp \
        python3-ijson \
        w3m \
        graphviz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install additional build dependencies for Linux kernel
RUN apt-get update && apt-get build-dep -y linux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and extract spacemit toolchain
RUN wget -q http://archive.spacemit.com/toolchain/spacemit-toolchain-linux-glibc-x86_64-v1.0.0.tar.xz -O - | tar -Jx -C /opt

# Set locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections \
    && echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections \
    && dpkg-reconfigure --frontend=noninteractive locales

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV TZ Asia/Shanghai

# Set timezone
RUN ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && dpkg-reconfigure --frontend=noninteractive tzdata

# Create build directory
RUN mkdir -p /build
WORKDIR /build

CMD ["/bin/bash"]
