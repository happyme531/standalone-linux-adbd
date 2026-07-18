# Static Linux TCP adbd

This branch adds a daemon-only build of ADB 36.0.1 for normal Linux systems.
It is intended for development boards whose vendor `adbd` has an old 4 KiB
transport payload and poor TCP throughput.

## Scope and security

The target is deliberately limited to TCP and VSOCK. Android USB FunctionFS,
framework authentication, TLS pairing, JDWP, and mDNS are not included. The
daemon advertises only features that this Linux build actually implements.

Authentication is disabled. Do not expose its listening port to an untrusted
network, especially when the service starts `adbd` as root. Restrict access
with a dedicated interface, firewall, or network namespace.

The Linux compatibility layer also accepts the legacy `ADB_TCP_PORT` and
`ADBD_SHELL` environment variables used by Rockchip's `usbdevice.service`.
`ADBD_PORT` remains the preferred generic port variable.

## Pinned source dependencies

The repository records every dependency as a shallow-capable submodule:

| Component | Version or commit |
| --- | --- |
| android-tools | 36.0.1 (`cda6dcc98cc486685e3eae0190b55ff6968f4795`) |
| brotli | v1.1.0 (`ed738e842d2fbdf2d6459e39267a633c4a9b2f5d`) |
| lz4 | v1.10.0 (`ebb370ca83af193212df4dcbadcc5d87bc0de2f0`) |
| zstd | v1.5.7 (`f8745da6ff1ad1e7bab384bd1f9d742439278e99`) |

Brotli, LZ4, zstd, fmt, libbase, libcutils, and liblog are linked statically.
No system compression development packages or vcpkg installation are needed.

## Build

For a native build on an AArch64 board:

```sh
scripts/build-linux-adbd.sh
file build/linux-adbd/vendor/adbd
ldd build/linux-adbd/vendor/adbd
```

For an x86_64 host with Debian/Ubuntu's AArch64 cross toolchain:

```sh
CMAKE_TOOLCHAIN_FILE="$PWD/cmake/toolchains/aarch64-linux-gnu.cmake" \
  scripts/build-linux-adbd.sh build/linux-adbd-aarch64
```

The first configure applies the repository's patch series to the initialized
AOSP submodules. Later runs detect the final ADB patch and configure with
`ANDROID_TOOLS_PATCH_VENDOR=OFF` so the process is repeatable.

glibc emits warnings for static `getaddrinfo` and passwd/group lookups. The
binary has no ELF `DT_NEEDED` entries, but native builds remain the safest
choice when the target uses an older glibc/NSS setup. The GitHub workflow also
cross-builds and checks a stripped AArch64 artifact with QEMU.

## Verified RK3588 result

The deployed build was compiled natively on Debian 11 AArch64 with GCC 10.2.1
and glibc 2.31, then tested over a 2.5 Gbit/s Ethernet link with a 512 MiB
incompressible file and tmpfs at both ends.

| Daemon | Push | Pull |
| --- | ---: | ---: |
| rktoolkit legacy adbd | 15.3 MiB/s | 15.5 MiB/s |
| ADB 36.0.1 Linux adbd | about 278 MiB/s | 210.2 MiB/s |

The push figure uses shell wall time. ADB's internal push timer can report more
than line rate because it stops before all buffered TCP data has drained. Both
transferred files matched SHA256
`78f5933c5564b918f655650e1c32dcfe3424e663ab4b3c21fd3afaa54a47e605`.

## Board deployment and rollback

Keep a board-local copy of the vendor daemon before replacement. The tested
installation uses:

```sh
sudo systemctl stop usbdevice.service
sudo mv /usr/bin/adbd /usr/bin/adbd.rktoolkit-legacy
sudo install -o root -g root -m 0755 \
  build/linux-adbd/vendor/adbd /usr/bin/adbd
sudo systemctl start usbdevice.service
```

Rollback by stopping the service, restoring the saved file to
`/usr/bin/adbd`, and starting the service again. USB behavior is outside the
scope of this TCP-only daemon.
