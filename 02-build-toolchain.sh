#!/bin/bash
#
# PiCLFS toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export LC_ALL=POSIX
export PARALLEL_JOBS=18
export CONFIG_LINUX_ARCH="arm64"
export CONFIG_TARGET="aarch64-linux-gnu"
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export WORKSPACE_DIR=$PWD
export SOURCES_DIR=$WORKSPACE_DIR/sources
export OUTPUT_DIR=$WORKSPACE_DIR/out
export BUILD_DIR=$OUTPUT_DIR/build
export TOOLS_DIR=$OUTPUT_DIR/tools
export SYSROOT_DIR=$TOOLS_DIR/$CONFIG_TARGET/sysroot

export CFLAGS="-O2 -I$TOOLS_DIR/include"
export CPPFLAGS="-O2 -I$TOOLS_DIR/include"
export CXXFLAGS="-O2 -I$TOOLS_DIR/include"
export LDFLAGS="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib"
export PATH="$TOOLS_DIR/bin:$TOOLS_DIR/sbin:$PATH"

export PKG_CONFIG="$TOOLS_DIR/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_LIBDIR="$TOOLS_DIR/lib/pkgconfig:$TOOLS_DIR/share/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_STRIP_AND_DELETE_DOCS=1

# End of optional parameters
function step() {
    echo -e "\e[7m\e[1m>>> $1\e[0m"
}

function success() {
    echo -e "\e[1m\e[32m$1\e[0m"
}

function error() {
    echo -e "\e[1m\e[31m$1\e[0m"
}

function extract() {
    case $1 in
        *.tgz) tar -zxf $1 -C $2 ;;
        *.tar.gz) tar -zxf $1 -C $2 ;;
        *.tar.bz2) tar -jxf $1 -C $2 ;;
        *.tar.xz) tar -Jxf $1 -C $2 ;;
    esac
}

function check_environment_variable {
    if ! [[ -d $SOURCES_DIR ]] ; then
        error "Please download tarball files!"
        error "Run 'make download'."
        exit 1
    fi
}

function check_tarballs {
    LIST_OF_TARBALLS="
    elfutils-0.186.tar.bz2
    fakeroot_1.27.orig.tar.gz
    busybox-1.34.1.tar.bz2
    e2fsprogs-1.46.5.tar.gz
    autoconf-2.71.tar.xz
    automake-1.16.1.tar.xz
    binutils-2.38.tar.xz
    bison-3.8.tar.xz
    gawk-5.1.1.tar.xz
    gcc-11.2.0.tar.xz
    glibc-2.35.tar.xz
    gmp-6.2.1.tar.xz
    libtool-2.4.6.tar.xz
    m4-1.4.18.tar.xz
    mpc-1.2.1.tar.gz
    mpfr-4.1.0.tar.xz
    mtools-4.0.38.tar.bz2
    openssl-1.1.1m.tar.gz
    dosfstools-4.2.tar.gz
    confuse-3.3.tar.xz
    genimage-15.tar.xz
    1.20220120.tar.gz
    flex-2.6.4.tar.gz
    util-linux-2.37.4.tar.xz
    pkgconf-1.8.0.tar.xz
    zlib-1.2.11.tar.xz
    "

    for tarball in $LIST_OF_TARBALLS ; do
        if ! [[ -f $SOURCES_DIR/$tarball ]] ; then
            error "Can't find '$tarball'!"
            exit 1
        fi
    done
}

function do_strip {
    set +o errexit
    if [[ $CONFIG_STRIP_AND_DELETE_DOCS = 1 ]] ; then
        strip --strip-debug $TOOLS_DIR/lib/*
        strip --strip-unneeded $TOOLS_DIR/{,s}bin/*
        rm -rf $TOOLS_DIR/{,share}/{info,man,doc}
    fi
}

function timer {
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local stime=$1
        etime=$(date '+%s')
        if [[ -z "$stime" ]]; then stime=$etime; fi
        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%02d:%02d:%02d' $dh $dm $ds
    fi
}

check_environment_variable
check_tarballs
total_build_time=$(timer)

step "[1/25] Create toolchain directory."
rm -rf $BUILD_DIR $TOOLS_DIR
mkdir -pv $BUILD_DIR $TOOLS_DIR
ln -svf . $TOOLS_DIR/usr

step "[2/25] Create the sysroot directory"
mkdir -pv $SYSROOT_DIR
ln -svf . $SYSROOT_DIR/usr
mkdir -pv $SYSROOT_DIR/lib
if [[ "$CONFIG_LINUX_ARCH" = "arm" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "arm64" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib64
fi

step "[3/25] Pkgconf"
extract $SOURCES_DIR/pkgconf-1.8.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/pkgconf-1.8.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-dependency-tracking )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkgconf-1.8.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/pkgconf-1.8.0
cat > $TOOLS_DIR/bin/pkg-config << "EOF"
#!/bin/sh
PKGCONFDIR=$(dirname $0)
DEFAULT_PKG_CONFIG_LIBDIR=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib/pkgconfig:${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/share/pkgconfig
DEFAULT_PKG_CONFIG_SYSROOT_DIR=${PKGCONFDIR}/../@STAGING_SUBDIR@
DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/include
DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib

PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-${DEFAULT_PKG_CONFIG_LIBDIR}} \
	PKG_CONFIG_SYSROOT_DIR=${PKG_CONFIG_SYSROOT_DIR:-${DEFAULT_PKG_CONFIG_SYSROOT_DIR}} \
	PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKG_CONFIG_SYSTEM_INCLUDE_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH}} \
	PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKG_CONFIG_SYSTEM_LIBRARY_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH}} \
	exec ${PKGCONFDIR}/pkgconf @STATIC@ "$@"
EOF
chmod 755 $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STAGING_SUBDIR@,$SYSROOT_DIR,g" $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STATIC@,," $TOOLS_DIR/bin/pkg-config
rm -rf $BUILD_DIR/pkgconf-1.8.0

step "[4/25] M4 1.4.18"
extract $SOURCES_DIR/m4-1.4.18.tar.xz $BUILD_DIR
( cd $BUILD_DIR/m4-1.4.18 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4-1.4.18
make -j$PARALLEL_JOBS install -C $BUILD_DIR/m4-1.4.18
rm -rf $BUILD_DIR/m4-1.4.18

step "[5/25] Libtool 2.4.6"
extract $SOURCES_DIR/libtool-2.4.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool-2.4.6 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool-2.4.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libtool-2.4.6
rm -rf $BUILD_DIR/libtool-2.4.6

step "[6/25] Autoconf"
extract $SOURCES_DIR/autoconf-2.71.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf-2.71 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf-2.71
make -j$PARALLEL_JOBS install -C $BUILD_DIR/autoconf-2.71
rm -rf $BUILD_DIR/autoconf-2.71

step "[7/25] Automake"
extract $SOURCES_DIR/automake-1.16.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake-1.16.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake-1.16.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/automake-1.16.1
mkdir -p $SYSROOT_DIR/usr/share/aclocal
rm -rf $BUILD_DIR/automake-1.16.1

step "[8/25] Zlib"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11 && ./configure --prefix=$TOOLS_DIR )
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "[9/25] Util-linux"
extract $SOURCES_DIR/util-linux-2.37.4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/util-linux-2.37.4 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-python \
    --enable-libblkid \
    --enable-libmount \
    --enable-libuuid \
    --without-ncurses \
    --without-ncursesw \
    --without-tinfo \
    --disable-makeinstall-chown \
    --disable-agetty \
    --disable-chfn-chsh \
    --disable-chmem \
    --disable-login \
    --disable-lslogins \
    --disable-mesg \
    --disable-more \
    --disable-newgrp \
    --disable-nologin \
    --disable-nsenter \
    --disable-pg \
    --disable-rfkill \
    --disable-schedutils \
    --disable-setpriv \
    --disable-setterm \
    --disable-su \
    --disable-sulogin \
    --disable-tunelp \
    --disable-ul \
    --disable-unshare \
    --disable-uuidd \
    --disable-vipw \
    --disable-wall \
    --disable-wdctl \
    --disable-write \
    --disable-zramctl )
make -j$PARALLEL_JOBS -C $BUILD_DIR/util-linux-2.37.4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/util-linux-2.37.4
rm -rf $BUILD_DIR/util-linux-2.37.4

step "[10/25] E2fsprogs"
extract $SOURCES_DIR/e2fsprogs-1.46.5.tar.gz $BUILD_DIR
( cd $BUILD_DIR/e2fsprogs-1.46.5 && \
    ac_cv_path_LDCONFIG=true \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-defrag \
    --disable-e2initrd-helper \
    --disable-fuse2fs \
    --disable-libblkid \
    --disable-libuuid \
    --disable-testio-debug \
    --enable-symlink-install \
    --enable-elf-shlibs \
    --with-crond-dir=no )
make -j$PARALLEL_JOBS -C $BUILD_DIR/e2fsprogs-1.46.5
make -j$PARALLEL_JOBS install -C $BUILD_DIR/e2fsprogs-1.46.5
rm -rf $BUILD_DIR/e2fsprogs-1.46.5

step "[11/25] Fakeroot"
extract $SOURCES_DIR/fakeroot_1.27.orig.tar.gz $BUILD_DIR
( cd $BUILD_DIR/fakeroot-1.27 && \
    ac_cv_header_sys_capability_h=no \
    ac_cv_func_capset=no \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/fakeroot-1.27
make -j$PARALLEL_JOBS install -C $BUILD_DIR/fakeroot-1.27
rm -rf $BUILD_DIR/fakeroot-1.27

step "[12/25] Bison"
extract $SOURCES_DIR/bison-3.8.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bison-3.8 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison-3.8
make -j$PARALLEL_JOBS install -C $BUILD_DIR/bison-3.8
rm -rf $BUILD_DIR/bison-3.8

step "[13/25] Gawk"
extract $SOURCES_DIR/gawk-5.1.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gawk-5.1.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-readline \
    --without-mpfr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.1.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gawk-5.1.1
rm -rf $BUILD_DIR/gawk-5.1.1

step "[14/25] Binutils"
extract $SOURCES_DIR/binutils-2.38.tar.xz $BUILD_DIR
mkdir -pv $BUILD_DIR/binutils-2.38/binutils-build
( cd $BUILD_DIR/binutils-2.38/binutils-build && \
    MAKEINFO=true \
    $BUILD_DIR/binutils-2.38/configure \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --disable-multilib \
    --disable-werror \
    --disable-shared \
    --enable-static \
    --with-sysroot=$SYSROOT_DIR \
    --enable-poison-system-directories \
    --disable-sim \
    --disable-gdb )
make -j$PARALLEL_JOBS configure-host -C $BUILD_DIR/binutils-2.38/binutils-build
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils-2.38/binutils-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/binutils-2.38/binutils-build
rm -rf $BUILD_DIR/binutils-2.38

step "[15/25] Gcc - Static"
tar -Jxf $SOURCES_DIR/gcc-11.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/gmp-6.2.1 $BUILD_DIR/gcc-11.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-11.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpc-1.2.1 $BUILD_DIR/gcc-11.2.0/mpc
mkdir -pv $BUILD_DIR/gcc-11.2.0/gcc-build
( cd $BUILD_DIR/gcc-11.2.0/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-11.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --disable-static \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --disable-libquadmath \
    --enable-tls \
    --enable-threads \
    --without-isl \
    --without-cloog \
    --with-abi="lp64" \
    --with-cpu=cortex-a72 \
    --enable-languages=c \
    --disable-shared \
    --without-headers \
    --disable-threads \
    --with-newlib \
    --disable-largefile )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes all-gcc all-target-libgcc -C $BUILD_DIR/gcc-11.2.0/gcc-build
make -j$PARALLEL_JOBS install-gcc install-target-libgcc -C $BUILD_DIR/gcc-11.2.0/gcc-build
rm -rf $BUILD_DIR/gcc-11.2.0

step "[16/25] Raspberry Pi Linux API Headers"
extract $SOURCES_DIR/1.20220120.tar.gz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-1.20220120
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH headers_check -C $BUILD_DIR/linux-1.20220120
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR headers_install -C $BUILD_DIR/linux-1.20220120
rm -rf $BUILD_DIR/linux-1.20220120

step "[17/25] glibc"
extract $SOURCES_DIR/glibc-2.35.tar.xz $BUILD_DIR
mkdir $BUILD_DIR/glibc-2.35/glibc-build
( cd $BUILD_DIR/glibc-2.35/glibc-build && \
    CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
    CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++" \
    AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar" \
    AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as" \
    LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" \
    RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib" \
    READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf" \
    STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip" \
    CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="-O2 " LDFLAGS="" \
    ac_cv_path_BASH_SHELL=/bin/sh \
    libc_cv_forced_unwind=yes \
    libc_cv_ssp=no \
    $BUILD_DIR/glibc-2.35/configure \
    --target=$CONFIG_TARGET \
    --host=$CONFIG_TARGET \
    --build=$CONFIG_HOST \
    --prefix=/usr \
    --enable-shared \
    --without-cvs \
    --disable-profile \
    --without-gd \
    --enable-obsolete-rpc \
    --enable-kernel=5.10 \
    --with-headers=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc-2.35/glibc-build
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc-2.35/glibc-build
rm -rf $BUILD_DIR/glibc-2.35

step "[18/25] Gcc - Final"
tar -Jxf $SOURCES_DIR/gcc-11.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/gmp-6.2.1 $BUILD_DIR/gcc-11.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-11.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpc-1.2.1 $BUILD_DIR/gcc-11.2.0/mpc
( cd $BUILD_DIR/gcc-11.2.0/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-11.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --disable-libquadmath \
    --enable-tls \
    --enable-threads \
    --with-abi="lp64" \
    --with-cpu=cortex-a72 \
    --enable-languages=c,c++ \
    --with-build-time-tools=$TOOLS_DIR/$CONFIG_TARGET/bin \
    --enable-shared \
    --disable-libgomp )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes -C $BUILD_DIR/gcc-11.2.0/gcc-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gcc-11.2.0/gcc-build
if [ ! -e $TOOLS_DIR/bin/$CONFIG_TARGET-cc ]; then
    ln -vf $TOOLS_DIR/bin/$CONFIG_TARGET-gcc $TOOLS_DIR/bin/$CONFIG_TARGET-cc
fi
rm -rf $BUILD_DIR/gcc-11.2.0

step "[19/25] Elfutils"
extract $SOURCES_DIR/elfutils-0.186.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/elfutils-0.186 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-debuginfod )
make -j$PARALLEL_JOBS -C $BUILD_DIR/elfutils-0.186
make -j$PARALLEL_JOBS install -C $BUILD_DIR/elfutils-0.186
rm -rf $BUILD_DIR/elfutils-0.186

step "[20/25] Dosfstools"
extract $SOURCES_DIR/dosfstools-4.2.tar.xz $BUILD_DIR
( cd $BUILD_DIR/dosfstools-4.2 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --enable-compat-symlinks )
make -j$PARALLEL_JOBS -C $BUILD_DIR/dosfstools-4.2
make -j$PARALLEL_JOBS install -C $BUILD_DIR/dosfstools-4.2
rm -rf $BUILD_DIR/dosfstools-4.2

step "[21/25] libconfuse"
extract $SOURCES_DIR/confuse-3.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/confuse-3.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/confuse-3.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/confuse-3.3
rm -rf $BUILD_DIR/confuse-3.3

step "[22/25] Genimage"
extract $SOURCES_DIR/genimage-15.tar.xz $BUILD_DIR
( cd $BUILD_DIR/genimage-15 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/genimage-15
make -j$PARALLEL_JOBS install -C $BUILD_DIR/genimage-15
rm -rf $BUILD_DIR/genimage-15

step "[23/25] Flex"
extract $SOURCES_DIR/flex-2.6.4.tar.gz $BUILD_DIR
( cd $BUILD_DIR/flex-2.6.4 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j$PARALLEL_JOBS -C $BUILD_DIR/flex-2.6.4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/flex-2.6.4
rm -rf $BUILD_DIR/flex-2.6.4

step "[24/25] Mtools"
extract $SOURCES_DIR/mtools-4.0.38.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/mtools-4.0.38 && \
    ac_cv_lib_bsd_gethostbyname=no \
    ac_cv_lib_bsd_main=no \
    ac_cv_path_INSTALL_INFO= \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j1 -C $BUILD_DIR/mtools-4.0.38
make -j1 install -C $BUILD_DIR/mtools-4.0.38
rm -rf $BUILD_DIR/mtools-4.0.38

step "[25/25] Openssl"
extract $SOURCES_DIR/openssl-1.1.1m.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl-1.1.1m && \
    ./config \
    --prefix=$TOOLS_DIR \
    --openssldir=$TOOLS_DIR/etc/ssl \
    --libdir=lib \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    shared \
    zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1m
make -j$PARALLEL_JOBS install -C $BUILD_DIR/openssl-1.1.1m
rm -rf $BUILD_DIR/openssl-1.1.1m

do_strip

success "\nTotal toolchain build time: $(timer $total_build_time)\n"
