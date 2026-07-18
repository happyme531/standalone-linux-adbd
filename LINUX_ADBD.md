# Static standalone Linux adbd

This branch adds a daemon-only build of ADB 36.0.1 for normal Linux systems.
It targets development boards whose vendor `adbd` has an old 4 KiB transport
payload or lacks a usable FunctionFS implementation. TCP, VSOCK, and USB
FunctionFS can run at the same time.

## Scope and security

USB support is enabled by default. Set `ANDROID_TOOLS_ADBD_USB=OFF` when
invoking the build script for a smaller TCP/VSOCK-only build.

The standalone target omits Android framework authentication, TLS pairing,
JDWP, mDNS, and system-property lifecycle integration. It advertises only the
ADB features that it implements. Authentication is disabled, so do not expose
its listening port or USB connector to untrusted clients, especially when the
service starts `adbd` as root.

The compatibility layer accepts the legacy `ADB_TCP_PORT` and `ADBD_SHELL`
environment variables used by Rockchip's `usbdevice.service`. `ADBD_PORT`
remains the preferred generic port variable.

USB mode expects the platform's gadget manager to create and mount an `adb`
FunctionFS instance at `/dev/usb-ffs/adb`. The daemon writes full-speed,
high-speed, SuperSpeed, and Microsoft OS descriptors, then opens the bulk
endpoints. It does not create a configfs gadget or select a UDC itself.

## Pinned source dependencies

The repository records every dependency as a shallow-capable submodule:

| Component | Version or commit |
| --- | --- |
| android-tools | 36.0.1 (`cda6dcc98cc486685e3eae0190b55ff6968f4795`) |
| brotli | v1.1.0 (`ed738e842d2fbdf2d6459e39267a633c4a9b2f5d`) |
| lz4 | v1.10.0 (`ebb370ca83af193212df4dcbadcc5d87bc0de2f0`) |
| zstd | v1.5.7 (`f8745da6ff1ad1e7bab384bd1f9d742439278e99`) |

Brotli, LZ4, zstd, fmt, libasyncio, libbase, libcutils, and liblog are linked
statically. No system compression development packages or vcpkg installation
are needed.

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

The first configure applies the repository patch series to the initialized
AOSP submodules. Later runs detect the final ADB patch and configure with
`ANDROID_TOOLS_PATCH_VENDOR=OFF`, making the script repeatable.

glibc emits warnings for static `getaddrinfo` and passwd/group lookups. The
binary has no ELF `DT_NEEDED` entries, but native builds remain the safest
choice when the target uses an older glibc/NSS setup. CI cross-builds a
stripped AArch64 artifact and smoke-tests startup with QEMU.

## Windows WinUSB discovery

FunctionFS supplies ADB's `WINUSB` compatible ID and
`DeviceInterfaceGUID`, but the gadget manager must also enable the configfs
Microsoft OS descriptor entry before binding the UDC. Rockchip's
`usbdevice` helper prepares the signature and vendor code but normally enables
the entry only for MTP.

Install the included hook on Rockchip systems:

```sh
sudo install -D -o root -g root -m 0755 \
  contrib/rockchip-usbdevice/adbd-ms-os-desc.sh \
  /etc/usbdevice.d/adbd-ms-os-desc.sh
sudo systemctl restart usbdevice.service
```

Other gadget managers need the equivalent of `os_desc/use=1` after adbd opens
FunctionFS ep0 and before the UDC is bound. Without that configfs step, ADB
still works with a preinstalled driver, but a fresh Windows machine cannot
discover the WinUSB compatible ID automatically.

## Verified RK3588 result

The deployed build was compiled natively on Debian 11 AArch64 with GCC 10.2.1
and glibc 2.31. The binary is fully static and runs under Rockchip's unchanged
`usbdevice.service` with TCP 5555 and FunctionFS active together.

TCP tests used incompressible tmpfs files at both ends. The original 512 MiB
comparison over Ethernet was:

| Daemon | Push | Pull |
| --- | ---: | ---: |
| rktoolkit legacy adbd | 15.3 MiB/s | 15.5 MiB/s |
| ADB 36.0.1 standalone adbd | about 278 MiB/s | 210.2 MiB/s |

After USB was enabled, a 256 MiB uncompressed TCP regression reached about
289 MB/s push by wall time and 210.6 MB/s pull. High-speed USB 2.0 reached
about 42.5 MB/s push by wall time and 42.8-44.1 MB/s pull. The ADB client's
internal push timer reported impossible values above the USB 2.0 line rate
because it stopped before queued writes drained; those figures are not used
here. Every source, board, and round-trip SHA-256 matched.

The USB descriptor probe retrieved the 18-byte `MSFT100` string, the 40-byte
Extended Compat ID containing `WINUSB`, and the 142-byte Extended Properties
descriptor containing `{F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}`.

## Board deployment and rollback

Keep a board-local copy of the vendor daemon before replacement. A typical
installation is:

```sh
sudo systemctl stop usbdevice.service
sudo cp -a /usr/bin/adbd /usr/bin/adbd.vendor-backup
sudo install -o root -g root -m 0755 \
  build/linux-adbd/vendor/adbd /usr/bin/adbd
sudo systemctl start usbdevice.service
```

Install the Rockchip hook from the Windows section when automatic WinUSB
discovery is required. Roll back by stopping the service, restoring the saved
daemon, removing the hook if it was installed, and starting the service again.
