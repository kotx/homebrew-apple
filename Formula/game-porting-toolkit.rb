def stage(&block)
     ohai "Staging #{cached_location} in #{pwd}"
     system "tar", "-xf", cached_location, "--include=sources/wine/*", "--strip-components=1"
     yield if block_given?
end
version "1.0.4"
desc "Apple Game Porting Toolkit"
homepage "https://developer.apple.com/"
url "https://media.codeweavers.com/pub/crossover/source/crossover-sources-22.1.1.tar.gz", using: TarballDownloadStrategy
sha256 "cdfe282ce33788bd4f969c8bfb1d3e2de060eb6c296fa1c3cdf4e4690b8b1831"
patch :DATA

depends_on arch: :x86_64
depends_on "game-porting-toolkit-compiler"
depends_on "bison" => :build
uses_from_macos "flex" => :build
depends_on "mingw-w64" => :build
depends_on "gstreamer"
depends_on "pkg-config" # to find the rest of the runtime dependencies

@@named_deps = ["zlib", # must be explicitly added to PKG_CONFIG_PATH
                    "freetype",
                    "sdl2",
                    "libgphoto2",
                    "faudio",
                    "jpeg",
                    "libpng",
                    "mpg123",
                    "libtiff",
                    "libgsm",
                    "glib",
                    "gnutls",
                    "libusb",
                    "gettext",
                    "openssl@1.1",
                    "sane-backends",
                    "molten-vk"]
@@named_deps.each do |dep|
     depends_on dep
end

def install
     # Bypass the Homebrew shims to build native binaries with the dedicated compiler.
     # (PE binaries will be built with mingw32-gcc.)
     compiler = Formula["game-porting-toolkit-compiler"]
     compiler_options = ["CC=#{compiler.bin}/clang",
                         "CXX=#{compiler.bin}/clang++"]

     # Becuase we are bypassing the Homebrew shims, we need to make the dependencies’ headers visible.
     # (mingw32-gcc will automatically make the mingw-w64 headers visible.)
     @@named_deps.each do |dep|
     formula = Formula[dep]
     ENV.append_to_cflags "-I#{formula.include}"
     ENV.append "LDFLAGS", "-L#{formula.lib}"
     end

     # Glib & GStreamer have also has a non-standard include path
     ENV.append "GSTREAMER_CFLAGS", "-I#{Formula['gstreamer'].include}/gstreamer-1.0"
     ENV.append "GSTREAMER_LIBS", "-L#{Formula['gstreamer'].lib}"
     ENV.append "GSTREAMER_CFLAGS", "-I#{Formula['glib'].include}/glib-2.0"
     ENV.append "GSTREAMER_CFLAGS", "-I#{Formula['glib'].lib}/glib-2.0/include"
     ENV.append "GSTREAMER_LIBS", "-lglib-2.0 -lgmodule-2.0 -lgstreamer-1.0 -lgstaudio-1.0 -lgstvideo-1.0 -lgstgl-1.0 -lgobject-2.0"

     # We also need to tell the linker to add Homebrew to the rpath stack.
     # Whisky also needs @loader_path/../lib/ for its own libraries.
     ENV.append "LDFLAGS", "-lSystem -L#{HOMEBREW_PREFIX}/lib -Wl,-rpath,@loader_path/../lib,-rpath,#{HOMEBREW_PREFIX}/lib -Wl,-rpath,@executable_path/../lib/external"

     # Common compiler flags for both Mach-O and PE binaries.
     ENV.append_to_cflags "-O3 -Wno-implicit-function-declaration -Wno-format -Wno-deprecated-declarations -Wno-incompatible-pointer-types"
     # Use an older deployment target to avoid new dyld behaviors.
     # The custom compiler is too old to accept "13.0", so we use "10.14".
     ENV["MACOSX_DEPLOYMENT_TARGET"] = "10.14"

     wine_configure_options = ["--prefix=#{prefix}",
     wine64_configure_options = ["--enable-win64",
                              "--with-gnutls",
                              "--with-freetype",
                              "--with-gstreamer"]

     wine32_configure_options = ["--enable-win32on64",
                              "--with-wine64=../wine64-build",
                              "--without-gstreamer",
                              "--without-gphoto",
                              "--without-sane",
                              "--without-krb5",
                              "--disable-winedbg",
                              "--without-openal",
                              "--without-unwind",
                              "--without-usb"]

     # Build 64-bit Wine first.
     mkdir buildpath/"wine64-build" do
     system buildpath/"wine/configure", *wine_configure_options, *wine64_configure_options, *compiler_options
     system "make"
     end

     # Now build 32-on-64 Wine.
     mkdir buildpath/"wine32-build" do
     system buildpath/"wine/configure", *wine_configure_options, *wine32_configure_options, *compiler_options
     system "make"
     end

     # Install both builds.
     cd "wine64-build" do
     system "make", "install"
     end

     cd "wine32-build" do
     system "make", "install"
     end
end

def post_install
     chmod 0664, dylib
     MachO::Tools.change_dylib_id(dylib, "@rpath/#{File.basename(dylib)}")
     MachO.codesign!(dylib)
     chmod 0444, dylib
     end
def caveats
     return unless latest_version_installed?
     "Please follow the instructions in the Game Porting Toolkit README to complete installation."
end
test do
     system bin/"wine64", "--version"
end
From 5ab86b527aa6d27e91ede528925c633559135ff3 Mon Sep 17 00:00:00 2001
From: ohaiibuzzle <23693150+ohaiibuzzle@users.noreply.github.com>
Date: Wed, 11 Oct 2023 02:17:27 +0700
Subject: [PATCH 1/2] base gptk patches

---
wine/configure                                |   44 +
wine/configure.ac                             |   14 +
wine/dlls/advapi32/advapi.c                   |   48 +
wine/dlls/advapi32/advapi32.spec              |    8 +-
wine/dlls/advapi32/tests/perf.c               |  109 +
.../Makefile.in                               |    1 +
.../api-ms-win-core-psm-appnotify-l1-1-0.spec |    2 +
.../api-ms-win-power-base-l1-1-0/Makefile.in  |    1 +
.../api-ms-win-power-base-l1-1-0.spec         |    5 +
wine/dlls/atiadlxx/Makefile.in                |    8 +
wine/dlls/atiadlxx/atiadlxx.spec              | 1138 +++++++
wine/dlls/atiadlxx/atiadlxx_main.c            |  752 +++++
wine/dlls/crypt32/base64.c                    |  183 +
wine/dlls/crypt32/cert.c                      |    1 +
wine/dlls/crypt32/chain.c                     |   63 +-
wine/dlls/crypt32/decode.c                    |  246 +-
wine/dlls/crypt32/encode.c                    |    2 +-
wine/dlls/crypt32/object.c                    |    2 +-
wine/dlls/crypt32/str.c                       |  813 ++---
wine/dlls/crypt32/tests/base64.c              |  514 ++-
wine/dlls/crypt32/tests/cert.c                |  689 +++-
wine/dlls/crypt32/tests/chain.c               |   15 +
wine/dlls/crypt32/tests/encode.c              |  151 +-
wine/dlls/crypt32/tests/main.c                |    2 +-
wine/dlls/crypt32/tests/message.c             |   16 +-
wine/dlls/crypt32/tests/msg.c                 |    4 +-
wine/dlls/crypt32/tests/object.c              |  140 -
wine/dlls/crypt32/tests/oid.c                 |    4 +-
wine/dlls/crypt32/tests/store.c               |   32 +-
wine/dlls/crypt32/tests/str.c                 |  697 ++--
wine/dlls/crypt32/unixlib.c                   |   16 +-
wine/dlls/cryptnet/cryptnet_main.c            |   35 +-
wine/dlls/kernel32/kernel32.spec              |    2 +
wine/dlls/kernelbase/kernelbase.spec          |    6 +-
wine/dlls/kernelbase/memory.c                 |   30 +
wine/dlls/kernelbase/thread.c                 |   19 +
wine/dlls/mfmediaengine/Makefile.in           |    2 +
wine/dlls/mfmediaengine/main.c                | 1005 ++----
wine/dlls/mfmediaengine/tests/Makefile.in     |    3 +-
wine/dlls/mfmediaengine/tests/mfmediaengine.c |  566 +---
wine/dlls/mfplat/Makefile.in                  |    4 +-
wine/dlls/mfplat/aac_decoder.c                |  620 ++++
wine/dlls/mfplat/audioconvert.c               |  910 +++++
wine/dlls/mfplat/buffer.c                     |   83 +-
wine/dlls/mfplat/colorconvert.c               |  901 +++++
wine/dlls/mfplat/decode_transform.c           | 1218 +++++++
wine/dlls/mfplat/gst_guids.h                  |   23 +
wine/dlls/mfplat/gst_private.h                |  217 ++
wine/dlls/mfplat/h264_decoder.c               |  727 ++++
wine/dlls/mfplat/main.c                       |  660 ++--
wine/dlls/mfplat/media_source.c               | 2006 +++++++++++
wine/dlls/mfplat/mediatype.c                  |  142 +-
wine/dlls/mfplat/mfplat.c                     | 1036 ++++++
wine/dlls/mfplat/mfplat.spec                  |    6 +-
wine/dlls/mfplat/mfplat_private.h             |    6 +-
wine/dlls/mfplat/quartz_parser.c              | 1945 +++++++++++
wine/dlls/mfplat/queue.c                      |   14 +-
wine/dlls/mfplat/rsrc.rc                      |   28 +
wine/dlls/mfplat/sample.c                     |   27 +-
wine/dlls/mfplat/tests/Makefile.in            |    1 +
wine/dlls/mfplat/tests/mfplat.c               | 3007 ++++++++---------
wine/dlls/mfplat/unix_private.h               |   37 +
wine/dlls/mfplat/unixlib.h                    |  354 ++
wine/dlls/mfplat/wg_parser.c                  | 2584 ++++++++++++++
wine/dlls/mfplat/wg_transform.c               |  630 ++++
wine/dlls/mfplat/winegstreamer.rgs            |   14 +
wine/dlls/mfplat/winegstreamer.spec           |    6 +
wine/dlls/mfplat/winegstreamer_classes.idl    |   93 +
wine/dlls/mfplat/wm_asyncreader.c             | 1590 +++++++++
wine/dlls/mfplat/wm_reader.c                  | 2170 ++++++++++++
wine/dlls/mfplat/wm_syncreader.c              |  407 +++
wine/dlls/mfplat/wma_decoder.c                |  861 +++++
wine/dlls/mfreadwrite/reader.c                |   93 +-
wine/dlls/ntdll/loader.c                      |   10 +-
wine/dlls/ntdll/unix/loader.c                 |   46 +
wine/dlls/ntdll/unix/signal_x86_64.c          |   16 +
wine/dlls/ntdll/unix/system.c                 |   25 +-
wine/dlls/ntdll/unixlib.h                     |    6 +-
wine/dlls/qcap/Makefile.in                    |    1 +
wine/dlls/qcap/audiorecord.c                  |    8 +-
wine/dlls/qcap/avico.c                        |   26 +-
wine/dlls/qcap/avimux.c                       |   32 +-
wine/dlls/qcap/capturegraph.c                 |   15 +-
wine/dlls/qcap/filewriter.c                   |   17 +-
wine/dlls/qcap/tests/Makefile.in              |    1 +
wine/dlls/qcap/tests/audiorecord.c            |   82 +-
wine/dlls/qcap/tests/avico.c                  |  256 +-
wine/dlls/qcap/tests/avimux.c                 |  364 +-
wine/dlls/qcap/tests/capturegraph.c           |  194 +-
wine/dlls/qcap/tests/filewriter.c             |  320 +-
wine/dlls/qcap/tests/qcap.c                   |  114 +-
wine/dlls/qcap/tests/smartteefilter.c         |  482 +--
wine/dlls/qcap/tests/videocapture.c           |  232 +-
wine/dlls/qcap/v4l.c                          |    4 +-
wine/dlls/qcap/vfwcapture.c                   |   44 +-
wine/dlls/quartz/Makefile.in                  |    1 +
wine/dlls/quartz/acmwrapper.c                 |   24 +-
wine/dlls/quartz/avidec.c                     |   45 +-
wine/dlls/quartz/dsoundrender.c               |   40 +-
wine/dlls/quartz/filesource.c                 |   15 +-
wine/dlls/quartz/filtergraph.c                |  672 ++--
wine/dlls/quartz/filtermapper.c               |   96 +-
wine/dlls/quartz/main.c                       |    9 +-
wine/dlls/quartz/memallocator.c               |   44 +-
wine/dlls/quartz/passthrough.c                |    4 +-
wine/dlls/quartz/regsvr.c                     |    2 +-
wine/dlls/quartz/systemclock.c                |   15 +-
wine/dlls/quartz/tests/Makefile.in            |    1 +
wine/dlls/quartz/tests/acmwrapper.c           |  202 +-
wine/dlls/quartz/tests/avidec.c               |  510 +--
wine/dlls/quartz/tests/avisplit.c             |  608 ++--
wine/dlls/quartz/tests/dsoundrender.c         |  503 ++-
wine/dlls/quartz/tests/filesource.c           |  496 +--
wine/dlls/quartz/tests/filtergraph.c          | 1828 +++++-----
wine/dlls/quartz/tests/filtermapper.c         |  120 +-
wine/dlls/quartz/tests/memallocator.c         |  358 +-
wine/dlls/quartz/tests/mpegsplit.c            |  658 ++--
wine/dlls/quartz/tests/passthrough.c          |   32 +-
wine/dlls/quartz/tests/systemclock.c          |   88 +-
wine/dlls/quartz/tests/videorenderer.c        | 1222 ++++---
wine/dlls/quartz/tests/vmr7.c                 | 1388 ++++----
wine/dlls/quartz/tests/vmr9.c                 | 1693 +++++-----
wine/dlls/quartz/tests/waveparser.c           |  388 +--
wine/dlls/quartz/videorenderer.c              |   12 +-
wine/dlls/quartz/vmr9.c                       |  312 +-
wine/dlls/quartz/window.c                     |   83 +-
wine/dlls/windows.gaming.input/Makefile.in    |    6 +
wine/dlls/windows.gaming.input/async.c        |  647 ++++
wine/dlls/windows.gaming.input/classes.idl    |    2 +
.../windows.gaming.input/condition_effect.c   |  288 ++
.../windows.gaming.input/constant_effect.c    |  275 ++
wine/dlls/windows.gaming.input/controller.c   |   30 +-
.../windows.gaming.input/force_feedback.c     |  801 +++++
wine/dlls/windows.gaming.input/gamepad.c      |   32 +-
wine/dlls/windows.gaming.input/main.c         |    9 +
.../windows.gaming.input/periodic_effect.c    |  326 ++
wine/dlls/windows.gaming.input/private.h      |   24 +
wine/dlls/windows.gaming.input/provider.c     |   47 +-
wine/dlls/windows.gaming.input/provider.idl   |  119 +
wine/dlls/windows.gaming.input/racing_wheel.c |    9 +-
wine/dlls/windows.gaming.input/ramp_effect.c  |  278 ++
wine/dlls/windows.gaming.input/vector.c       |    6 +-
.../windows.gaming.ui.gamebar/Makefile.in     |    8 +
.../windows.gaming.ui.gamebar/classes.idl     |   33 +
wine/dlls/windows.gaming.ui.gamebar/main.c    |  282 ++
.../tests/Makefile.in                         |    5 +
.../windows.gaming.ui.gamebar/tests/gamebar.c |   91 +
.../windows.gaming.ui.gamebar.spec            |    3 +
wine/dlls/wined3d/adapter_vk.c                |    2 +-
wine/dlls/winegstreamer/Makefile.in           |    7 +-
wine/dlls/winegstreamer/aac_decoder.c         |  620 ++++
wine/dlls/winegstreamer/audioconvert.c        |  390 ++-
wine/dlls/winegstreamer/colorconvert.c        |  901 +++++
wine/dlls/winegstreamer/decode_transform.c    | 1218 +++++++
wine/dlls/winegstreamer/gst_private.h         |   87 +-
wine/dlls/winegstreamer/h264_decoder.c        |  400 ++-
wine/dlls/winegstreamer/main.c                |  139 +-
wine/dlls/winegstreamer/media_source.c        |  136 +-
wine/dlls/winegstreamer/mfplat.c              |  364 +-
wine/dlls/winegstreamer/quartz_parser.c       |  116 +-
wine/dlls/winegstreamer/unix_private.h        |    5 +-
wine/dlls/winegstreamer/unixlib.h             |  101 +-
wine/dlls/winegstreamer/wg_parser.c           | 1183 ++++++-
wine/dlls/winegstreamer/wg_transform.c        |  716 ++--
.../winegstreamer/winegstreamer_classes.idl   |   14 +-
wine/dlls/winegstreamer/wm_asyncreader.c      |  133 +-
wine/dlls/winegstreamer/wm_reader.c           |  115 +-
wine/dlls/winegstreamer/wm_syncreader.c       |   34 +-
wine/dlls/winegstreamer/wma_decoder.c         |  490 ++-
wine/dlls/winemac.drv/macdrv_main.c           |   59 +
wine/dlls/wintrust/softpub.c                  |   91 +-
wine/dlls/wintrust/tests/softpub.c            |  581 ++++
wine/dlls/wintrust/wintrust_main.c            |    4 +
wine/include/Makefile.in                      |    3 +
wine/include/Makefile.in.orig                 |  904 +++++
wine/include/distversion.h                    |   12 +
wine/include/memoryapi.h                      |   46 +
wine/include/perflib.h                        |   27 +
wine/include/processthreadsapi.h              |   15 +
wine/include/winbase.h                        |    1 +
wine/include/wincrypt.h                       |   11 +-
wine/include/windows.foundation.numerics.idl  |   39 +
.../windows.gaming.input.forcefeedback.idl    |  170 +
wine/include/windows.gaming.input.idl         |   13 +
wine/include/windows.gaming.ui.idl            |   61 +
wine/include/wine/strmbase.h                  |    4 +-
wine/include/wintrust.h                       |    6 +-
wine/libs/strmbase/Makefile.in                |    1 +
wine/libs/strmbase/dispatch.c                 |    4 +-
wine/libs/strmbase/filter.c                   |   64 +-
wine/libs/strmbase/mediatype.c                |   38 +-
wine/libs/strmbase/pin.c                      |   45 +-
wine/libs/strmbase/pospass.c                  |   17 +-
wine/libs/strmbase/renderer.c                 |    2 +-
wine/libs/strmbase/seeking.c                  |    7 +-
wine/libs/strmiids/strmiids.c                 |    2 +-
wine/loader/preloader_mac.c                   |    4 +
wine/tools/make_specfiles                     |    5 +
198 files changed, 43199 insertions(+), 13101 deletions(-)
create mode 100644 wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/Makefile.in
create mode 100644 wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/api-ms-win-core-psm-appnotify-l1-1-0.spec
create mode 100644 wine/dlls/api-ms-win-power-base-l1-1-0/Makefile.in
create mode 100644 wine/dlls/api-ms-win-power-base-l1-1-0/api-ms-win-power-base-l1-1-0.spec
create mode 100644 wine/dlls/atiadlxx/Makefile.in
create mode 100644 wine/dlls/atiadlxx/atiadlxx.spec
create mode 100644 wine/dlls/atiadlxx/atiadlxx_main.c
create mode 100644 wine/dlls/mfplat/aac_decoder.c
create mode 100644 wine/dlls/mfplat/audioconvert.c
create mode 100644 wine/dlls/mfplat/colorconvert.c
create mode 100644 wine/dlls/mfplat/decode_transform.c
create mode 100644 wine/dlls/mfplat/gst_guids.h
create mode 100644 wine/dlls/mfplat/gst_private.h
create mode 100644 wine/dlls/mfplat/h264_decoder.c
create mode 100644 wine/dlls/mfplat/media_source.c
create mode 100644 wine/dlls/mfplat/mfplat.c
create mode 100644 wine/dlls/mfplat/quartz_parser.c
create mode 100644 wine/dlls/mfplat/rsrc.rc
create mode 100644 wine/dlls/mfplat/unix_private.h
create mode 100644 wine/dlls/mfplat/unixlib.h
create mode 100644 wine/dlls/mfplat/wg_parser.c
create mode 100644 wine/dlls/mfplat/wg_transform.c
create mode 100644 wine/dlls/mfplat/winegstreamer.rgs
create mode 100644 wine/dlls/mfplat/winegstreamer.spec
create mode 100644 wine/dlls/mfplat/winegstreamer_classes.idl
create mode 100644 wine/dlls/mfplat/wm_asyncreader.c
create mode 100644 wine/dlls/mfplat/wm_reader.c
create mode 100644 wine/dlls/mfplat/wm_syncreader.c
create mode 100644 wine/dlls/mfplat/wma_decoder.c
create mode 100644 wine/dlls/windows.gaming.input/async.c
create mode 100644 wine/dlls/windows.gaming.input/condition_effect.c
create mode 100644 wine/dlls/windows.gaming.input/constant_effect.c
create mode 100644 wine/dlls/windows.gaming.input/force_feedback.c
create mode 100644 wine/dlls/windows.gaming.input/periodic_effect.c
create mode 100644 wine/dlls/windows.gaming.input/ramp_effect.c
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/Makefile.in
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/classes.idl
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/main.c
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/tests/Makefile.in
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/tests/gamebar.c
create mode 100644 wine/dlls/windows.gaming.ui.gamebar/windows.gaming.ui.gamebar.spec
create mode 100644 wine/dlls/winegstreamer/aac_decoder.c
create mode 100644 wine/dlls/winegstreamer/colorconvert.c
create mode 100644 wine/dlls/winegstreamer/decode_transform.c
create mode 100644 wine/include/Makefile.in.orig
create mode 100644 wine/include/distversion.h
create mode 100644 wine/include/memoryapi.h
create mode 100644 wine/include/windows.foundation.numerics.idl
create mode 100644 wine/include/windows.gaming.ui.idl

diff --git a/wine/configure b/wine/configure
index 2d57c7e08..475f1229f 100755
--- a/wine/configure
+++ b/wine/configure
@@ -950,6 +950,9 @@ enable_amstream
enable_apisetschema
enable_apphelp
enable_appwiz_cpl
+enable_atiadlxx
+enable_api_ms_win_power_base_l1_1_0
enable_atl
enable_atl100
enable_atl110
@@ -1421,6 +1424,7 @@ enable_wimgapi
enable_win32u
enable_windows_devices_enumeration
enable_windows_gaming_input
+enable_windows_gaming_ui_gamebar
enable_windows_globalization
enable_windows_media_devices
enable_windows_media_speech
@@ -9933,6 +9937,41 @@ ac_compiler_gnu=$ac_cv_c_compiler_gnu
     wine_can_build_preloader=yes
     WINEPRELOADER_LDFLAGS="-nostartfiles -nodefaultlibs -e _start -ldylib1.o -Wl,-image_base,0x7d400000,-segalign,0x1000,-pagezero_size,0x1000,-sectcreate,__TEXT,__info_plist,loader/wine_info.plist,-segaddr,WINE_4GB_RESERVE,0x100000000"
+        { printf "%s\n" "$as_me:${as_lineno-$LINENO}: checking whether the compiler supports -Wl,-ld_classic" >&5
+printf %s "checking whether the compiler supports -Wl,-ld_classic... " >&6; }
+if test ${ac_cv_cflags__Wl__ld_classic+y}
+then :
+  printf %s "(cached) " >&6
+else $as_nop
+  ac_wine_try_cflags_saved=$CFLAGS
+CFLAGS="$CFLAGS -Wl,-ld_classic"
+cat confdefs.h - <<_ACEOF >conftest.$ac_ext
+/* end confdefs.h.  */
+int main(int argc, char **argv) { return 0; }
+_ACEOF
+if ac_fn_c_try_link "$LINENO"
+then :
+  ac_cv_cflags__Wl__ld_classic=yes
+else $as_nop
+  ac_cv_cflags__Wl__ld_classic=no
+fi
+rm -f core conftest.err conftest.$ac_objext conftest.beam \
+    conftest$ac_exeext conftest.$ac_ext
+CFLAGS=$ac_wine_try_cflags_saved
+fi
+{ printf "%s\n" "$as_me:${as_lineno-$LINENO}: result: $ac_cv_cflags__Wl__ld_classic" >&5
+printf "%s\n" "$ac_cv_cflags__Wl__ld_classic" >&6; }
+if test "x$ac_cv_cflags__Wl__ld_classic" = xyes
+then :
+  ld_classic_flags="-Wl,-ld_classic"
+                     ld_classic_flags="-Wl,-ld_classic"
+fi
+    WINELOADER_LDFLAGS="$ld_classic_flags $WINELOADER_LDFLAGS"
+    WINEPRELOADER_LDFLAGS="$ld_classic_flags $WINEPRELOADER_LDFLAGS"
+    UNIXLDFLAGS="$ld_classic_flags $WINEPRELOADER_LDFLAGS"
+    LDDLLFLAGS="$ld_classic_flags $LDDLLFLAGS"
     { printf "%s\n" "$as_me:${as_lineno-$LINENO}: checking whether the compiler supports -Wl,-no_new_main -e _main" >&5
printf %s "checking whether the compiler supports -Wl,-no_new_main -e _main... " >&6; }
if test ${ac_cv_cflags__Wl__no_new_main__e__main+y}
@@ -21776,6 +21815,9 @@ wine_fn_config_makefile dlls/apisetschema enable_apisetschema
wine_fn_config_makefile dlls/apphelp enable_apphelp
wine_fn_config_makefile dlls/apphelp/tests enable_tests
wine_fn_config_makefile dlls/appwiz.cpl enable_appwiz_cpl
+wine_fn_config_makefile dlls/atiadlxx enable_atiadlxx
+wine_fn_config_makefile dlls/api-ms-win-core-psm-appnotify-l1-1-0 enable_api_ms_win_core_psm_appnotify_l1_1_0
+wine_fn_config_makefile dlls/api-ms-win-power-base-l1-1-0 enable_api_ms_win_power_base_l1_1_0
wine_fn_config_makefile dlls/atl enable_atl
wine_fn_config_makefile dlls/atl/tests enable_tests
wine_fn_config_makefile dlls/atl100 enable_atl100
@@ -22525,6 +22567,8 @@ wine_fn_config_makefile dlls/windebug.dll16 enable_win16
wine_fn_config_makefile dlls/windows.devices.enumeration enable_windows_devices_enumeration
wine_fn_config_makefile dlls/windows.gaming.input enable_windows_gaming_input
wine_fn_config_makefile dlls/windows.gaming.input/tests enable_tests
+wine_fn_config_makefile dlls/windows.gaming.ui.gamebar enable_windows_gaming_ui_gamebar 
+wine_fn_config_makefile dlls/windows.gaming.ui.gamebar/tests enable_tests
wine_fn_config_makefile dlls/windows.globalization enable_windows_globalization
wine_fn_config_makefile dlls/windows.globalization/tests enable_tests
wine_fn_config_makefile dlls/windows.media.devices enable_windows_media_devices
diff --git a/wine/configure.ac b/wine/configure.ac
index 50c50d15e..c57664857 100644
--- a/wine/configure.ac
+++ b/wine/configure.ac
@@ -724,6 +724,16 @@ case $host_os in

     wine_can_build_preloader=yes
     WINEPRELOADER_LDFLAGS="-nostartfiles -nodefaultlibs -e _start -ldylib1.o -Wl,-image_base,0x7d400000,-segalign,0x1000,-pagezero_size,0x1000,-sectcreate,__TEXT,__info_plist,loader/wine_info.plist,-segaddr,WINE_4GB_RESERVE,0x100000000"
+    dnl The linker that ships with Xcode 15 beta 4 doesn’t support -segaddr unless you also pass -ld_classic.
+    WINE_TRY_CFLAGS([-Wl,-ld_classic],
+                    [ld_classic_flags="-Wl,-ld_classic"
+                     ld_classic_flags="-Wl,-ld_classic"])
+    WINELOADER_LDFLAGS="$ld_classic_flags $WINELOADER_LDFLAGS"
+    WINEPRELOADER_LDFLAGS="$ld_classic_flags $WINEPRELOADER_LDFLAGS"
+    UNIXLDFLAGS="$ld_classic_flags $WINEPRELOADER_LDFLAGS"
+    LDDLLFLAGS="$ld_classic_flags $LDDLLFLAGS"
     WINE_TRY_CFLAGS([-Wl,-no_new_main -e _main],
                    [WINEPRELOADER_LDFLAGS="-Wl,-no_new_main $WINEPRELOADER_LDFLAGS"
                    WINE_TRY_CFLAGS([-Wl,-no_new_main -e _main -mmacosx-version-min=10.7 -nostartfiles -nodefaultlibs],
@@ -2424,6 +2434,8 @@ WINE_CONFIG_MAKEFILE(dlls/apisetschema)
WINE_CONFIG_MAKEFILE(dlls/apphelp)
WINE_CONFIG_MAKEFILE(dlls/apphelp/tests)
WINE_CONFIG_MAKEFILE(dlls/appwiz.cpl)
+WINE_CONFIG_MAKEFILE(dlls/atiadlxx)
+WINE_CONFIG_MAKEFILE(dlls/api-ms-win-power-base-l1-1-0)
WINE_CONFIG_MAKEFILE(dlls/atl)
WINE_CONFIG_MAKEFILE(dlls/atl/tests)
WINE_CONFIG_MAKEFILE(dlls/atl100)
@@ -3173,6 +3185,8 @@ WINE_CONFIG_MAKEFILE(dlls/windebug.dll16,enable_win16)
WINE_CONFIG_MAKEFILE(dlls/windows.devices.enumeration)
WINE_CONFIG_MAKEFILE(dlls/windows.gaming.input)
WINE_CONFIG_MAKEFILE(dlls/windows.gaming.input/tests)
+WINE_CONFIG_MAKEFILE(dlls/windows.gaming.ui.gamebar)
+WINE_CONFIG_MAKEFILE(dlls/windows.gaming.ui.gamebar/tests)
WINE_CONFIG_MAKEFILE(dlls/windows.globalization)
WINE_CONFIG_MAKEFILE(dlls/windows.globalization/tests)
WINE_CONFIG_MAKEFILE(dlls/windows.media.devices)
diff --git a/wine/dlls/advapi32/advapi.c b/wine/dlls/advapi32/advapi.c
index 6497ea22f..f7d6e9732 100644
--- a/wine/dlls/advapi32/advapi.c
+++ b/wine/dlls/advapi32/advapi.c
@@ -32,6 +32,7 @@
#include "winerror.h"
#include "wincred.h"
#include "wct.h"
+#include "perflib.h"

#include "wine/debug.h"

@@ -334,3 +335,50 @@ BOOL WINAPI GetThreadWaitChain(HWCT handle, DWORD_PTR ctx, DWORD flags, DWORD th
     SetLastError(ERROR_NOT_SUPPORTED);
     return FALSE;
}
+ULONG WINAPI PerfCloseQueryHandle( HANDLE query )
+{
+    FIXME( "query %p stub.\n", query );
+    return ERROR_SUCCESS;
+}
+ULONG WINAPI PerfOpenQueryHandle( const WCHAR *machine, HANDLE *query )
+{
+    FIXME( "machine %s, query %p.\n", debugstr_w(machine), query );
+    if (!query) return ERROR_INVALID_PARAMETER;
+    *query = (HANDLE)0xdeadbeef;
+    return ERROR_SUCCESS;
+ULONG WINAPI PerfAddCounters( HANDLE query, PERF_COUNTER_IDENTIFIER *id, DWORD size )
+    FIXME( "query %p, id %p, size %lu stub.\n", query, id, size );
+    if (!id || size < sizeof(*id) || id->Size < sizeof(*id)) return ERROR_INVALID_PARAMETER;
+
+    id->Status = ERROR_WMI_GUID_NOT_FOUND;
+    return ERROR_SUCCESS;
+ULONG WINAPI PerfQueryCounterData( HANDLE query, PERF_DATA_HEADER *data, DWORD data_size, DWORD *size_needed )
+    FIXME( "query %p, data %p, data_size %lu, size_needed %p stub.\n", query, data, data_size, size_needed );
+    if (!size_needed) return ERROR_INVALID_PARAMETER;
+    *size_needed = sizeof(PERF_DATA_HEADER);
+    if (!data || data_size < sizeof(PERF_DATA_HEADER)) return ERROR_NOT_ENOUGH_MEMORY;
+    data->dwTotalSize = sizeof(PERF_DATA_HEADER);
+    data->dwNumCounters = 0;
+    QueryPerformanceCounter( (LARGE_INTEGER *)&data->PerfTimeStamp );
+    QueryPerformanceFrequency( (LARGE_INTEGER *)&data->PerfFreq );
+    GetSystemTimeAsFileTime( (FILETIME *)&data->PerfTime100NSec );
+    FileTimeToSystemTime( (FILETIME *)&data->PerfTime100NSec, &data->SystemTime );
+
+    return ERROR_SUCCESS;
diff --git a/wine/dlls/advapi32/advapi32.spec b/wine/dlls/advapi32/advapi32.spec
index 3b5f587d4..1c3f59bb7 100644
--- a/wine/dlls/advapi32/advapi32.spec
+++ b/wine/dlls/advapi32/advapi32.spec
@@ -553,8 +553,8 @@
@ stdcall -ret64 -import OpenTraceW(ptr)
# @ stub OperationEnd
# @ stub OperationStart
-# @ stub PerfAddCounters
-# @ stub PerfCloseQueryHandle
+@ stdcall PerfAddCounters(long ptr long)
+@ stdcall PerfCloseQueryHandle(long)
@ stdcall -import PerfCreateInstance(long ptr wstr long)
# @ stub PerfDecrementULongCounterValue
# @ stub PerfDecrementULongLongCounterValue
@@ -564,8 +564,8 @@
# @ stub PerfEnumerateCounterSetInstances
# @ stub PerfIncrementULongCounterValue
# @ stub PerfIncrementULongLongCounterValue
-# @ stub PerfOpenQueryHandle
-# @ stub PerfQueryCounterData
+@ stdcall PerfOpenQueryHandle(wstr ptr)
+@ stdcall PerfQueryCounterData(long ptr long ptr)
# @ stub PerfQueryCounterInfo
# @ stub PerfQueryCounterSetRegistrationInfo
# @ stub PerfQueryInstance
diff --git a/wine/dlls/advapi32/tests/perf.c b/wine/dlls/advapi32/tests/perf.c
index fc07a09d3..34b6e9528 100644
--- a/wine/dlls/advapi32/tests/perf.c
+++ b/wine/dlls/advapi32/tests/perf.c
@@ -25,9 +25,31 @@
#include "winerror.h"
#include "perflib.h"
#include "winperf.h"
+#include "winternl.h"

#include "wine/test.h"

+#include "initguid.h"
+#define DEFINE_FUNCTION(name) static typeof(name) *p##name;
+DEFINE_FUNCTION(PerfCloseQueryHandle);
+DEFINE_FUNCTION(PerfOpenQueryHandle);
+DEFINE_FUNCTION(PerfAddCounters);
+DEFINE_FUNCTION(PerfQueryCounterData);
+#undef DEFINE_FUNCTION
+static void init_functions(void)
+{
+    HANDLE hadvapi = GetModuleHandleA("advapi32.dll");
+#define GET_FUNCTION(name) p##name = (void *)GetProcAddress(hadvapi, #name)
+    GET_FUNCTION(PerfCloseQueryHandle);
+    GET_FUNCTION(PerfOpenQueryHandle);
+    GET_FUNCTION(PerfAddCounters);
+    GET_FUNCTION(PerfQueryCounterData);
+#undef GET_FUNCTION
+}
static ULONG WINAPI test_provider_callback(ULONG code, void *buffer, ULONG size)
{
     ok(0, "Provider callback called.\n");
@@ -188,7 +210,94 @@ void test_provider_init(void)
     ok(!ret, "Got unexpected ret %lu.\n", ret);
}

+DEFINE_GUID(TestCounterGUID, 0x12345678, 0x1234, 0x5678, 0x12, 0x34, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33);
+static ULONG64 trunc_nttime_ms(ULONG64 t)
+{
+    return (t / 10000) * 10000;
+}
+static void test_perf_counters(void)
+{
+    LARGE_INTEGER freq, qpc1, qpc2, nttime1, nttime2, systime;
+    char buffer[sizeof(PERF_COUNTER_IDENTIFIER) + 8];
+    PERF_COUNTER_IDENTIFIER *counter_id;
+    PERF_DATA_HEADER dh;
+    HANDLE query;
+    DWORD size;
+    ULONG ret;
+    if (!pPerfOpenQueryHandle)
+        win_skip("PerfOpenQueryHandle not found.\n");
+        return;
+    }
+    ret = pPerfOpenQueryHandle(NULL, NULL);
+    ok(ret == ERROR_INVALID_PARAMETER, "got ret %lu.\n", ret);
+    ret = pPerfOpenQueryHandle(NULL, &query);
+    ok(!ret, "got ret %lu.\n", ret);
+    counter_id = (PERF_COUNTER_IDENTIFIER *)buffer;
+    memset(buffer, 0, sizeof(buffer));
+    counter_id->CounterSetGuid = TestCounterGUID;
+    counter_id->CounterId = PERF_WILDCARD_COUNTER;
+    counter_id->InstanceId = PERF_WILDCARD_COUNTER;
+    ret = pPerfAddCounters(query, counter_id, sizeof(*counter_id));
+    ok(ret == ERROR_INVALID_PARAMETER, "got ret %lu.\n", ret);
+    counter_id->Size = sizeof(*counter_id);
+    ret = pPerfAddCounters(query, counter_id, 8);
+    ok(ret == ERROR_INVALID_PARAMETER, "got ret %lu.\n", ret);
+    ret = pPerfAddCounters(query, counter_id, sizeof(*counter_id));
+    ok(!ret, "got ret %lu.\n", ret);
+    ok(counter_id->Status == ERROR_WMI_GUID_NOT_FOUND, "got Status %#lx.\n", counter_id->Status);
+    ret = pPerfQueryCounterData(query, NULL, 0, NULL);
+    ok(ret == ERROR_INVALID_PARAMETER, "got ret %lu.\n", ret);
+    size = 0xdeadbeef;
+    ret = pPerfQueryCounterData(query, NULL, 0, &size);
+    ok(ret == ERROR_NOT_ENOUGH_MEMORY, "got ret %lu.\n", ret);
+    ok(size == sizeof(dh), "got size %lu.\n", size);
+    ret = pPerfQueryCounterData(query, &dh, sizeof(dh), NULL);
+    ok(ret == ERROR_INVALID_PARAMETER, "got ret %lu.\n", ret);
+    QueryPerformanceFrequency(&freq);
+    QueryPerformanceCounter(&qpc1);
+    NtQuerySystemTime(&nttime1);
+    size = 0xdeadbeef;
+    ret = pPerfQueryCounterData(query, &dh, sizeof(dh), &size);
+    QueryPerformanceCounter(&qpc2);
+    NtQuerySystemTime(&nttime2);
+    SystemTimeToFileTime(&dh.SystemTime, (FILETIME *)&systime);
+    ok(!ret, "got ret %lu.\n", ret);
+    ok(size == sizeof(dh), "got size %lu.\n", size);
+    ok(dh.dwTotalSize == sizeof(dh), "got dwTotalSize %lu.\n", dh.dwTotalSize);
+    ok(!dh.dwNumCounters, "got dwNumCounters %lu.\n", dh.dwNumCounters);
+    ok(dh.PerfFreq == freq.QuadPart, "got PerfFreq %I64u.\n", dh.PerfFreq);
+    ok(dh.PerfTimeStamp >= qpc1.QuadPart && dh.PerfTimeStamp <= qpc2.QuadPart,
+            "got PerfTimeStamp %I64u, qpc1 %I64u, qpc2 %I64u.\n",
+            dh.PerfTimeStamp, qpc1.QuadPart, qpc2.QuadPart);
+    ok(dh.PerfTime100NSec >= nttime1.QuadPart && dh.PerfTime100NSec <= nttime2.QuadPart,
+            "got PerfTime100NSec %I64u, nttime1 %I64u, nttime2 %I64u.\n",
+            dh.PerfTime100NSec, nttime1.QuadPart, nttime2.QuadPart);
+    ok(systime.QuadPart >= trunc_nttime_ms(nttime1.QuadPart) && systime.QuadPart <= trunc_nttime_ms(nttime2.QuadPart),
+            "got systime %I64u, nttime1 %I64u, nttime2 %I64u, %d.\n",
+            systime.QuadPart, nttime1.QuadPart, nttime2.QuadPart, dh.SystemTime.wMilliseconds);
+    ret = pPerfCloseQueryHandle(query);
+    ok(!ret, "got ret %lu.\n", ret);
+}
START_TEST(perf)
{
+    init_functions();
     test_provider_init();
+    test_perf_counters();
}
diff --git a/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/Makefile.in b/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/Makefile.in
new file mode 100644
index 000000000..8a3d2ad98
--- /dev/null
+++ b/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/Makefile.in
@@ -0,0 +1 @@
+MODULE    = api-ms-win-core-psm-appnotify-l1-1-0.dll
diff --git a/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/api-ms-win-core-psm-appnotify-l1-1-0.spec b/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/api-ms-win-core-psm-appnotify-l1-1-0.spec
new file mode 100644
index 000000000..8b069d66e
--- /dev/null
+++ b/wine/dlls/api-ms-win-core-psm-appnotify-l1-1-0/api-ms-win-core-psm-appnotify-l1-1-0.spec
@@ -0,0 +1,2 @@
+@ stub RegisterAppStateChangeNotification
+@ stub UnregisterAppStateChangeNotification
diff --git a/wine/dlls/api-ms-win-power-base-l1-1-0/Makefile.in b/wine/dlls/api-ms-win-power-base-l1-1-0/Makefile.in
new file mode 100644
index 000000000..8b26d4be8
--- /dev/null
+++ b/wine/dlls/api-ms-win-power-base-l1-1-0/Makefile.in
@@ -0,0 +1 @@
+MODULE    = api-ms-win-power-base-l1-1-0.dll
diff --git a/wine/dlls/api-ms-win-power-base-l1-1-0/api-ms-win-power-base-l1-1-0.spec b/wine/dlls/api-ms-win-power-base-l1-1-0/api-ms-win-power-base-l1-1-0.spec
new file mode 100644
index 000000000..dd056946a
--- /dev/null
+++ b/wine/dlls/api-ms-win-power-base-l1-1-0/api-ms-win-power-base-l1-1-0.spec
@@ -0,0 +1,5 @@
+@ stdcall CallNtPowerInformation(long ptr long ptr long) powrprof.CallNtPowerInformation
+@ stdcall GetPwrCapabilities(ptr) powrprof.GetPwrCapabilities
+@ stdcall PowerDeterminePlatformRoleEx(long) powrprof.PowerDeterminePlatformRoleEx
+@ stdcall PowerRegisterSuspendResumeNotification(long ptr ptr) powrprof.PowerRegisterSuspendResumeNotification
+@ stub PowerUnregisterSuspendResumeNotification
diff --git a/wine/dlls/atiadlxx/Makefile.in b/wine/dlls/atiadlxx/Makefile.in
new file mode 100644
index 000000000..fd9b8abf6
--- /dev/null
+++ b/wine/dlls/atiadlxx/Makefile.in
@@ -0,0 +1,8 @@
+EXTRADEFS = -DWINE_NO_LONG_TYPES
+MODULE = atiadlxx.dll
+IMPORTS = dxgi
+EXTRADLLFLAGS = -mno-cygwin -Wb,--prefer-native
+C_SRCS = \
+	atiadlxx_main.c
diff --git a/wine/dlls/atiadlxx/atiadlxx.spec b/wine/dlls/atiadlxx/atiadlxx.spec
index 000000000..222fb744c
+++ b/wine/dlls/atiadlxx/atiadlxx.spec
@@ -0,0 +1,1138 @@
+@ stub ADL2_ADC_CurrentProfileFromDrv_Get
+@ stub ADL2_ADC_Display_AdapterDeviceProfileEx_Get
+@ stub ADL2_ADC_DrvDataToProfile_Copy
+@ stub ADL2_ADC_FindClosestMode_Get
+@ stub ADL2_ADC_IsDevModeEqual_Get
+@ stub ADL2_ADC_Profile_Apply
+@ stub ADL2_APO_AudioDelayAdjustmentInfo_Get
+@ stub ADL2_APO_AudioDelay_Restore
+@ stub ADL2_APO_AudioDelay_Set
+@ stub ADL2_AdapterLimitation_Caps
+@ stub ADL2_AdapterX2_Caps
+@ stub ADL2_Adapter_AMDAndNonAMDDIsplayClone_Get
+@ stdcall ADL2_Adapter_ASICFamilyType_Get(long long ptr ptr)
+@ stub ADL2_Adapter_ASICInfo_Get
+@ stub ADL2_Adapter_Accessibility_Get
+@ stub ADL2_Adapter_AceDefaults_Restore
+@ stub ADL2_Adapter_Active_Get
+@ stub ADL2_Adapter_Active_Set
+@ stub ADL2_Adapter_Active_SetPrefer
+@ stdcall ADL2_Adapter_AdapterInfoX2_Get(long ptr)
+@ stub ADL2_Adapter_AdapterInfoX3_Get
+@ stdcall ADL2_Adapter_AdapterInfoX4_Get(long long ptr ptr)
+@ stdcall ADL2_Adapter_AdapterInfo_Get(long ptr long)
+@ stub ADL2_Adapter_AdapterList_Disable
+@ stub ADL2_Adapter_AdapterLocationPath_Get
+@ stub ADL2_Adapter_Aspects_Get
+@ stub ADL2_Adapter_AudioChannelSplitConfiguration_Get
+@ stub ADL2_Adapter_AudioChannelSplit_Disable
+@ stub ADL2_Adapter_AudioChannelSplit_Enable
+@ stub ADL2_Adapter_BigSw_Info_Get
+@ stub ADL2_Adapter_BlackAndWhiteLevelSupport_Get
+@ stub ADL2_Adapter_BlackAndWhiteLevel_Get
+@ stub ADL2_Adapter_BlackAndWhiteLevel_Set
+@ stub ADL2_Adapter_BoardLayout_Get
+@ stub ADL2_Adapter_Caps
+@ stub ADL2_Adapter_ChipSetInfo_Get
+@ stub ADL2_Adapter_CloneTypes_Get
+@ stub ADL2_Adapter_ConfigMemory_Cap
+@ stub ADL2_Adapter_ConfigMemory_Get
+@ stub ADL2_Adapter_ConfigureState_Get
+@ stub ADL2_Adapter_ConnectionData_Get
+@ stub ADL2_Adapter_ConnectionData_Remove
+@ stub ADL2_Adapter_ConnectionData_Set
+@ stub ADL2_Adapter_ConnectionState_Get
+@ stub ADL2_Adapter_CrossDisplayPlatformInfo_Get
+@ stub ADL2_Adapter_CrossGPUClone_Disable
+@ stub ADL2_Adapter_CrossdisplayAdapterRole_Caps
+@ stub ADL2_Adapter_CrossdisplayInfoX2_Set
+@ stub ADL2_Adapter_CrossdisplayInfo_Get
+@ stub ADL2_Adapter_CrossdisplayInfo_Set
+@ stub ADL2_Adapter_CrossfireX2_Get
+@ stub ADL2_Adapter_Crossfire_Caps
+@ stub ADL2_Adapter_Crossfire_Get
+@ stub ADL2_Adapter_Crossfire_Set
+@ stub ADL2_Adapter_DefaultAudioChannelTable_Load
+@ stub ADL2_Adapter_Desktop_Caps
+@ stub ADL2_Adapter_Desktop_SupportedSLSGridTypes_Get
+@ stub ADL2_Adapter_DeviceID_Get
+@ stub ADL2_Adapter_DisplayAudioEndpoint_Enable
+@ stub ADL2_Adapter_DisplayAudioEndpoint_Mute
+@ stub ADL2_Adapter_DisplayAudioInfo_Get
+@ stub ADL2_Adapter_DisplayGTCCaps_Get
+@ stub ADL2_Adapter_Display_Caps
+@ stub ADL2_Adapter_DriverSettings_Get
+@ stub ADL2_Adapter_DriverSettings_Set
+@ stub ADL2_Adapter_ECC_ErrorInjection_Set
+@ stub ADL2_Adapter_ECC_ErrorRecords_Get
+@ stub ADL2_Adapter_EDC_ErrorInjection_Set
+@ stub ADL2_Adapter_EDC_ErrorRecords_Get
+@ stub ADL2_Adapter_EDIDManagement_Caps
+@ stub ADL2_Adapter_EmulationMode_Set
+@ stub ADL2_Adapter_ExtInfo_Get
+@ stub ADL2_Adapter_Feature_Caps
+@ stub ADL2_Adapter_FrameMetrics_Caps
+@ stub ADL2_Adapter_FrameMetrics_FrameDuration_Disable
+@ stub ADL2_Adapter_FrameMetrics_FrameDuration_Enable
+@ stub ADL2_Adapter_FrameMetrics_FrameDuration_Get
+@ stub ADL2_Adapter_FrameMetrics_FrameDuration_Start
+@ stub ADL2_Adapter_FrameMetrics_FrameDuration_Stop
+@ stub ADL2_Adapter_FrameMetrics_Get
+@ stub ADL2_Adapter_FrameMetrics_Start
+@ stub ADL2_Adapter_FrameMetrics_Stop
+@ stub ADL2_Adapter_Gamma_Get
+@ stub ADL2_Adapter_Gamma_Set
+@ stdcall ADL2_Adapter_Graphic_Core_Info_Get(ptr long ptr)
+@ stub ADL2_Adapter_HBC_Caps
+@ stub ADL2_Adapter_HBM_ECC_UC_Check
+@ stub ADL2_Adapter_Headless_Get
+@ stub ADL2_Adapter_ID_Get
+@ stub ADL2_Adapter_IsGamingDriver_Info_Get
+@ stub ADL2_Adapter_LocalDisplayConfig_Get
+@ stub ADL2_Adapter_LocalDisplayConfig_Set
+@ stub ADL2_Adapter_LocalDisplayState_Get
+@ stub ADL2_Adapter_MVPU_Set
+@ stub ADL2_Adapter_MaxCursorSize_Get
+@ stdcall ADL2_Adapter_MemoryInfo2_Get(long long ptr)
+@ stdcall ADL2_Adapter_MemoryInfo_Get(ptr long ptr)
+@ stub ADL2_Adapter_MirabilisSupport_Get
+@ stub ADL2_Adapter_ModeSwitch
+@ stub ADL2_Adapter_ModeTimingOverride_Caps
+@ stub ADL2_Adapter_Modes_ReEnumerate
+@ stub ADL2_Adapter_NumberOfActivatableSources_Get
+@ stdcall ADL2_Adapter_NumberOfAdapters_Get(ptr ptr)
+@ stub ADL2_Adapter_ObservedClockInfo_Get
+@ stub ADL2_Adapter_PMLog_Start
+@ stub ADL2_Adapter_PMLog_Stop
+@ stub ADL2_Adapter_PMLog_Support_Get
+@ stub ADL2_Adapter_PreFlipPostProcessing_Disable
+@ stub ADL2_Adapter_PreFlipPostProcessing_Enable
+@ stub ADL2_Adapter_PreFlipPostProcessing_Get_Status
+@ stub ADL2_Adapter_PreFlipPostProcessing_Select_LUT_Algorithm
+@ stub ADL2_Adapter_PreFlipPostProcessing_Select_LUT_Buffer
+@ stub ADL2_Adapter_PreFlipPostProcessing_Unselect_LUT_Buffer
+@ stub ADL2_Adapter_Primary_Get
+@ stub ADL2_Adapter_Primary_Set
+@ stub ADL2_Adapter_RAS_ErrorInjection_Set
+@ stub ADL2_Adapter_RegValueInt_Get
+@ stub ADL2_Adapter_RegValueInt_Set
+@ stub ADL2_Adapter_RegValueString_Get
+@ stub ADL2_Adapter_RegValueString_Set
+@ stub ADL2_Adapter_SWInfo_Get
+@ stub ADL2_Adapter_Speed_Caps
+@ stub ADL2_Adapter_Speed_Get
+@ stub ADL2_Adapter_Speed_Set
+@ stub ADL2_Adapter_SupportedConnections_Get
+@ stub ADL2_Adapter_TRNG_Get
+@ stub ADL2_Adapter_Tear_Free_Cap
+@ stub ADL2_Adapter_VRAMUsage_Get
+@ stub ADL2_Adapter_VariBrightEnable_Set
+@ stub ADL2_Adapter_VariBrightLevel_Get
+@ stub ADL2_Adapter_VariBrightLevel_Set
+@ stub ADL2_Adapter_VariBright_Caps
+@ stub ADL2_Adapter_VerndorID_Int_get
+@ stub ADL2_Adapter_VideoBiosInfo_Get
+@ stub ADL2_Adapter_VideoTheaterModeInfo_Get
+@ stub ADL2_Adapter_VideoTheaterModeInfo_Set
+@ stub ADL2_Adapter_XConnectSupport_Get
+@ stub ADL2_ApplicationProfilesX2_AppInterceptionList_Set
+@ stub ADL2_ApplicationProfilesX2_AppStartStopInfo_Get
+@ stub ADL2_ApplicationProfiles_AppInterceptionList_Set
+@ stub ADL2_ApplicationProfiles_AppInterception_Set
+@ stub ADL2_ApplicationProfiles_AppStartStopInfo_Get
+@ stub ADL2_ApplicationProfiles_AppStartStop_Resume
+@ stub ADL2_ApplicationProfiles_Applications_Get
+@ stub ADL2_ApplicationProfiles_ConvertToCompact
+@ stub ADL2_ApplicationProfiles_DriverAreaPrivacy_Get
+@ stub ADL2_ApplicationProfiles_GetCustomization
+@ stub ADL2_ApplicationProfiles_HitListsX2_Get
+@ stub ADL2_ApplicationProfiles_HitListsX3_Get
+@ stub ADL2_ApplicationProfiles_HitLists_Get
+@ stub ADL2_ApplicationProfiles_ProfileApplicationX2_Assign
+@ stub ADL2_ApplicationProfiles_ProfileApplication_Assign
+@ stub ADL2_ApplicationProfiles_ProfileOfAnApplicationX2_Search
+@ stub ADL2_ApplicationProfiles_ProfileOfAnApplication_InMemorySearch
+@ stub ADL2_ApplicationProfiles_ProfileOfAnApplication_Search
+@ stub ADL2_ApplicationProfiles_Profile_Create
+@ stub ADL2_ApplicationProfiles_Profile_Exist
+@ stub ADL2_ApplicationProfiles_Profile_Remove
+@ stub ADL2_ApplicationProfiles_PropertyType_Get
+@ stub ADL2_ApplicationProfiles_Release_Get
+@ stub ADL2_ApplicationProfiles_RemoveApplication
+@ stub ADL2_ApplicationProfiles_StatusInfo_Get
+@ stub ADL2_ApplicationProfiles_System_Reload
+@ stub ADL2_ApplicationProfiles_User_Load
+@ stub ADL2_ApplicationProfiles_User_Unload
+@ stub ADL2_Audio_CurrentSampleRate_Get
+@ stub ADL2_AutoTuningResult_Get
+@ stub ADL2_BOOST_Settings_Get
+@ stub ADL2_BOOST_Settings_Set
+@ stub ADL2_Blockchain_BlockchainMode_Caps
+@ stub ADL2_Blockchain_BlockchainMode_Get
+@ stub ADL2_Blockchain_BlockchainMode_Set
+@ stub ADL2_Blockchain_Hashrate_Set
+@ stub ADL2_CDS_UnsafeMode_Set
+@ stub ADL2_CHILL_SettingsX2_Get
+@ stub ADL2_CHILL_SettingsX2_Set
+@ stub ADL2_CV_DongleSettings_Get
+@ stub ADL2_CV_DongleSettings_Reset
+@ stub ADL2_CV_DongleSettings_Set
+@ stub ADL2_Chill_Caps_Get
+@ stub ADL2_Chill_Settings_Get
+@ stub ADL2_Chill_Settings_Notify
+@ stub ADL2_Chill_Settings_Set
+@ stub ADL2_CustomFan_Caps
+@ stub ADL2_CustomFan_Get
+@ stub ADL2_CustomFan_Set
+@ stub ADL2_DELAG_Settings_Get
+@ stub ADL2_DELAG_Settings_Set
+@ stub ADL2_DFP_AllowOnlyCETimings_Get
+@ stub ADL2_DFP_AllowOnlyCETimings_Set
+@ stub ADL2_DFP_BaseAudioSupport_Get
+@ stub ADL2_DFP_GPUScalingEnable_Get
+@ stub ADL2_DFP_GPUScalingEnable_Set
+@ stub ADL2_DFP_HDMISupport_Get
+@ stub ADL2_DFP_MVPUAnalogSupport_Get
+@ stub ADL2_DFP_PixelFormat_Caps
+@ stub ADL2_DFP_PixelFormat_Get
+@ stub ADL2_DFP_PixelFormat_Set
+@ stub ADL2_DVRSupport_Get
+@ stub ADL2_Desktop_DOPP_Enable
+@ stub ADL2_Desktop_DOPP_EnableX2
+@ stub ADL2_Desktop_Detach
+@ stub ADL2_Desktop_Device_Create
+@ stub ADL2_Desktop_Device_Destroy
+@ stub ADL2_Desktop_ExclusiveModeX2_Get
+@ stub ADL2_Desktop_HardwareCursor_SetBitmap
+@ stub ADL2_Desktop_HardwareCursor_SetPosition
+@ stub ADL2_Desktop_HardwareCursor_Toggle
+@ stub ADL2_Desktop_PFPAComplete_Set
+@ stub ADL2_Desktop_PFPAState_Get
+@ stub ADL2_Desktop_PrimaryInfo_Get
+@ stub ADL2_Desktop_TextureState_Get
+@ stub ADL2_Desktop_Texture_Enable
+@ stub ADL2_Device_PMLog_Device_Create
+@ stub ADL2_Device_PMLog_Device_Destroy
+@ stub ADL2_DisplayScaling_Set
+@ stub ADL2_Display_AdapterID_Get
+@ stub ADL2_Display_AdjustCaps_Get
+@ stub ADL2_Display_AdjustmentCoherent_Get
+@ stub ADL2_Display_AdjustmentCoherent_Set
+@ stub ADL2_Display_AudioMappingInfo_Get
+@ stub ADL2_Display_AvivoColor_Get
+@ stub ADL2_Display_AvivoCurrentColor_Set
+@ stub ADL2_Display_AvivoDefaultColor_Set
+@ stub ADL2_Display_BackLight_Get
+@ stub ADL2_Display_BackLight_Set
+@ stub ADL2_Display_BezelOffsetSteppingSize_Get
+@ stub ADL2_Display_BezelOffset_Set
+@ stub ADL2_Display_BezelSupported_Validate
+@ stub ADL2_Display_Capabilities_Get
+@ stub ADL2_Display_ColorCaps_Get
+@ stub ADL2_Display_ColorDepth_Get
+@ stub ADL2_Display_ColorDepth_Set
+@ stub ADL2_Display_ColorTemperatureSourceDefault_Get
+@ stub ADL2_Display_ColorTemperatureSource_Get
+@ stub ADL2_Display_ColorTemperatureSource_Set
+@ stub ADL2_Display_Color_Get
+@ stub ADL2_Display_Color_Set
+@ stub ADL2_Display_ConnectedDisplays_Get
+@ stub ADL2_Display_ContainerID_Get
+@ stub ADL2_Display_ControllerOverlayAdjustmentCaps_Get
+@ stub ADL2_Display_ControllerOverlayAdjustmentData_Get
+@ stub ADL2_Display_ControllerOverlayAdjustmentData_Set
+@ stub ADL2_Display_CustomizedModeListNum_Get
+@ stub ADL2_Display_CustomizedModeList_Get
+@ stub ADL2_Display_CustomizedMode_Add
+@ stub ADL2_Display_CustomizedMode_Delete
+@ stub ADL2_Display_CustomizedMode_Validate
+@ stub ADL2_Display_DCE_Get
+@ stub ADL2_Display_DCE_Set
+@ stub ADL2_Display_DDCBlockAccess_Get
+@ stdcall ADL2_Display_DDCInfo2_Get(ptr long long ptr)
+@ stub ADL2_Display_DDCInfo_Get
+@ stub ADL2_Display_Deflicker_Get
+@ stub ADL2_Display_Deflicker_Set
+@ stub ADL2_Display_DeviceConfig_Get
+@ stub ADL2_Display_DisplayContent_Cap
+@ stub ADL2_Display_DisplayContent_Get
+@ stub ADL2_Display_DisplayContent_Set
+@ stdcall ADL2_Display_DisplayInfo_Get(ptr long ptr ptr long)
+@ stub ADL2_Display_DisplayMapConfigX2_Set
+@ stdcall ADL2_Display_DisplayMapConfig_Get(ptr long ptr ptr ptr ptr long)
+@ stub ADL2_Display_DisplayMapConfig_PossibleAddAndRemove
+@ stub ADL2_Display_DisplayMapConfig_Set
+@ stub ADL2_Display_DisplayMapConfig_Validate
+@ stub ADL2_Display_DitherState_Get
+@ stub ADL2_Display_DitherState_Set
+@ stub ADL2_Display_Downscaling_Caps
+@ stub ADL2_Display_DpMstAuxMsg_Get
+@ stub ADL2_Display_DpMstInfo_Get
+@ stub ADL2_Display_DummyVirtual_Destroy
+@ stub ADL2_Display_DummyVirtual_Get
+@ stub ADL2_Display_EdidData_Get
+@ stub ADL2_Display_EdidData_Set
+@ stub ADL2_Display_EnumDisplays_Get
+@ stub ADL2_Display_FilterSVideo_Get
+@ stub ADL2_Display_FilterSVideo_Set
+@ stub ADL2_Display_ForcibleDisplay_Get
+@ stub ADL2_Display_ForcibleDisplay_Set
+@ stub ADL2_Display_FormatsOverride_Get
+@ stub ADL2_Display_FormatsOverride_Set
+@ stub ADL2_Display_FreeSyncState_Get
+@ stub ADL2_Display_FreeSyncState_Set
+@ stdcall ADL2_Display_FreeSync_Cap(ptr long long ptr)
+@ stub ADL2_Display_GamutMapping_Get
+@ stub ADL2_Display_GamutMapping_Reset
+@ stub ADL2_Display_GamutMapping_Set
+@ stub ADL2_Display_Gamut_Caps
+@ stub ADL2_Display_Gamut_Get
+@ stub ADL2_Display_Gamut_Set
+@ stub ADL2_Display_HDCP_Get
+@ stub ADL2_Display_HDCP_Set
+@ stub ADL2_Display_HDRState_Get
+@ stub ADL2_Display_HDRState_Set
+@ stub ADL2_Display_ImageExpansion_Get
+@ stub ADL2_Display_ImageExpansion_Set
+@ stub ADL2_Display_InfoPacket_Get
+@ stub ADL2_Display_InfoPacket_Set
+@ stub ADL2_Display_IsVirtual_Get
+@ stub ADL2_Display_LCDRefreshRateCapability_Get
+@ stub ADL2_Display_LCDRefreshRateOptions_Get
+@ stub ADL2_Display_LCDRefreshRateOptions_Set
+@ stub ADL2_Display_LCDRefreshRate_Get
+@ stub ADL2_Display_LCDRefreshRate_Set
+@ stub ADL2_Display_Limits_Get
+@ stub ADL2_Display_MVPUCaps_Get
+@ stub ADL2_Display_MVPUStatus_Get
+@ stub ADL2_Display_ModeTimingOverrideInfo_Get
+@ stub ADL2_Display_ModeTimingOverrideListX2_Get
+@ stub ADL2_Display_ModeTimingOverrideListX3_Get
+@ stub ADL2_Display_ModeTimingOverrideList_Get
+@ stub ADL2_Display_ModeTimingOverrideX2_Get
+@ stub ADL2_Display_ModeTimingOverrideX2_Set
+@ stub ADL2_Display_ModeTimingOverrideX3_Get
+@ stub ADL2_Display_ModeTimingOverride_Delete
+@ stub ADL2_Display_ModeTimingOverride_Get
+@ stub ADL2_Display_ModeTimingOverride_Set
+@ stdcall ADL2_Display_Modes_Get(ptr long long ptr ptr)
+@ stub ADL2_Display_Modes_Set
+@ stub ADL2_Display_Modes_X2_Get
+@ stub ADL2_Display_MonitorPowerState_Set
+@ stub ADL2_Display_NativeAUXChannel_Access
+@ stub ADL2_Display_NeedWorkaroundFor5Clone_Get
+@ stub ADL2_Display_NumberOfDisplays_Get
+@ stub ADL2_Display_ODClockConfig_Set
+@ stub ADL2_Display_ODClockInfo_Get
+@ stub ADL2_Display_Overlap_NotifyAdjustment
+@ stub ADL2_Display_Overlap_Set
+@ stub ADL2_Display_Overscan_Get
+@ stub ADL2_Display_Overscan_Set
+@ stub ADL2_Display_PixelFormatDefault_Get
+@ stub ADL2_Display_PixelFormat_Get
+@ stub ADL2_Display_PixelFormat_Set
+@ stub ADL2_Display_Position_Get
+@ stub ADL2_Display_Position_Set
+@ stub ADL2_Display_PossibleMapping_Get
+@ stub ADL2_Display_PossibleMode_Get
+@ stub ADL2_Display_PowerXpressActiveGPU_Get
+@ stub ADL2_Display_PowerXpressActiveGPU_Set
+@ stub ADL2_Display_PowerXpressActvieGPUR2_Get
+@ stub ADL2_Display_PowerXpressVersion_Get
+@ stub ADL2_Display_PowerXpress_AutoSwitchConfig_Get
+@ stub ADL2_Display_PowerXpress_AutoSwitchConfig_Set
+@ stub ADL2_Display_PreferredMode_Get
+@ stub ADL2_Display_PreservedAspectRatio_Get
+@ stub ADL2_Display_PreservedAspectRatio_Set
+@ stub ADL2_Display_Property_Get
+@ stub ADL2_Display_Property_Set
+@ stub ADL2_Display_RcDisplayAdjustment
+@ stub ADL2_Display_ReGammaCoefficients_Get
+@ stub ADL2_Display_ReGammaCoefficients_Set
+@ stub ADL2_Display_ReducedBlanking_Get
+@ stub ADL2_Display_ReducedBlanking_Set
+@ stub ADL2_Display_RegammaR1_Get
+@ stub ADL2_Display_RegammaR1_Set
+@ stub ADL2_Display_Regamma_Get
+@ stub ADL2_Display_Regamma_Set
+@ stub ADL2_Display_SLSBuilder_CommonMode_Get
+@ stub ADL2_Display_SLSBuilder_Create
+@ stub ADL2_Display_SLSBuilder_DisplaysCanBeNextCandidateInSLS_Get
+@ stub ADL2_Display_SLSBuilder_DisplaysCanBeNextCandidateToEnabled_Get
+@ stub ADL2_Display_SLSBuilder_Get
+@ stub ADL2_Display_SLSBuilder_IsActive_Notify
+@ stub ADL2_Display_SLSBuilder_MaxSLSLayoutSize_Get
+@ stub ADL2_Display_SLSBuilder_TimeOut_Get
+@ stub ADL2_Display_SLSBuilder_Update
+@ stub ADL2_Display_SLSGrid_Caps
+@ stub ADL2_Display_SLSMapConfigX2_Delete
+@ stub ADL2_Display_SLSMapConfigX2_Get
+@ stub ADL2_Display_SLSMapConfig_Create
+@ stub ADL2_Display_SLSMapConfig_Delete
+@ stub ADL2_Display_SLSMapConfig_Get
+@ stub ADL2_Display_SLSMapConfig_ImageCropType_Set
+@ stub ADL2_Display_SLSMapConfig_Rearrange
+@ stub ADL2_Display_SLSMapConfig_SetState
+@ stub ADL2_Display_SLSMapConfig_SupportedImageCropType_Get
+@ stub ADL2_Display_SLSMapConfig_Valid
+@ stub ADL2_Display_SLSMapIndexList_Get
+@ stub ADL2_Display_SLSMapIndex_Get
+@ stub ADL2_Display_SLSMiddleMode_Get
+@ stub ADL2_Display_SLSMiddleMode_Set
+@ stub ADL2_Display_SLSRecords_Get
+@ stub ADL2_Display_Sharpness_Caps
+@ stub ADL2_Display_Sharpness_Get
+@ stub ADL2_Display_Sharpness_Info_Get
+@ stub ADL2_Display_Sharpness_Set
+@ stub ADL2_Display_Size_Get
+@ stub ADL2_Display_Size_Set
+@ stub ADL2_Display_SourceContentAttribute_Get
+@ stub ADL2_Display_SourceContentAttribute_Set
+@ stub ADL2_Display_SplitDisplay_Caps
+@ stub ADL2_Display_SplitDisplay_Get
+@ stub ADL2_Display_SplitDisplay_RestoreDesktopConfiguration
+@ stub ADL2_Display_SplitDisplay_Set
+@ stub ADL2_Display_SupportedColorDepth_Get
+@ stub ADL2_Display_SupportedPixelFormat_Get
+@ stub ADL2_Display_SwitchingCapability_Get
+@ stub ADL2_Display_TVCaps_Get
+@ stub ADL2_Display_TargetTimingX2_Get
+@ stub ADL2_Display_TargetTiming_Get
+@ stub ADL2_Display_UnderScan_Auto_Get
+@ stub ADL2_Display_UnderScan_Auto_Set
+@ stub ADL2_Display_UnderscanState_Get
+@ stub ADL2_Display_UnderscanState_Set
+@ stub ADL2_Display_UnderscanSupport_Get
+@ stub ADL2_Display_Underscan_Get
+@ stub ADL2_Display_Underscan_Set
+@ stub ADL2_Display_Vector_Get
+@ stub ADL2_Display_ViewPort_Cap
+@ stub ADL2_Display_ViewPort_Get
+@ stub ADL2_Display_ViewPort_Set
+@ stub ADL2_Display_VirtualType_Get
+@ stub ADL2_Display_WriteAndReadI2C
+@ stub ADL2_Display_WriteAndReadI2CLargePayload
+@ stub ADL2_Display_WriteAndReadI2CRev_Get
+@ stub ADL2_ElmCompatibilityMode_Caps
+@ stub ADL2_ElmCompatibilityMode_Status_Get
+@ stub ADL2_ElmCompatibilityMode_Status_Set
+@ stub ADL2_ExclusiveModeGet
+@ stub ADL2_FPS_Caps
+@ stub ADL2_FPS_Settings_Get
+@ stub ADL2_FPS_Settings_Reset
+@ stub ADL2_FPS_Settings_Set
+@ stub ADL2_Feature_Settings_Get
+@ stub ADL2_Feature_Settings_Set
+@ stub ADL2_Flush_Driver_Data
+@ stub ADL2_GPUVMPageSize_Info_Get
+@ stub ADL2_GPUVMPageSize_Info_Set
+@ stub ADL2_GPUVerInfo_Get
+@ stub ADL2_GcnAsicInfo_Get
+@ stub ADL2_Graphics_IsDetachableGraphicsPlatform_Get
+@ stub ADL2_Graphics_IsGfx9AndAbove
+@ stub ADL2_Graphics_MantleVersion_Get
+@ stub ADL2_Graphics_Platform_Get
+@ stdcall ADL2_Graphics_VersionsX2_Get(ptr ptr)
+@ stub ADL2_Graphics_Versions_Get
+@ stub ADL2_Graphics_VulkanVersion_Get
+@ stub ADL2_HybridGraphicsGPU_Set
+@ stub ADL2_MGPUSLS_Status_Set
+@ stub ADL2_MMD_FeatureList_Get
+@ stub ADL2_MMD_FeatureValuesX2_Get
+@ stub ADL2_MMD_FeatureValuesX2_Set
+@ stub ADL2_MMD_FeatureValues_Get
+@ stub ADL2_MMD_FeatureValues_Set
+@ stub ADL2_MMD_FeaturesX2_Caps
+@ stub ADL2_MMD_Features_Caps
+@ stub ADL2_MMD_VideoAdjustInfo_Get
+@ stub ADL2_MMD_VideoAdjustInfo_Set
+@ stub ADL2_MMD_VideoColor_Caps
+@ stub ADL2_MMD_VideoColor_Get
+@ stub ADL2_MMD_VideoColor_Set
+@ stub ADL2_MMD_Video_Caps
+@ stub ADL2_Main_ControlX2_Create
+@ stdcall ADL2_Main_Control_Create(ptr long ptr)
+@ stdcall ADL2_Main_Control_Destroy()
+@ stub ADL2_Main_Control_GetProcAddress
+@ stub ADL2_Main_Control_IsFunctionValid
+@ stub ADL2_Main_Control_Refresh
+@ stub ADL2_Main_LogDebug_Set
+@ stub ADL2_Main_LogError_Set
+@ stub ADL2_New_QueryPMLogData_Get
+@ stub ADL2_Overdrive5_CurrentActivity_Get
+@ stub ADL2_Overdrive5_FanSpeedInfo_Get
+@ stub ADL2_Overdrive5_FanSpeedToDefault_Set
+@ stub ADL2_Overdrive5_FanSpeed_Get
+@ stub ADL2_Overdrive5_FanSpeed_Set
+@ stdcall ADL2_Overdrive5_ODParameters_Get(ptr long ptr)
+@ stub ADL2_Overdrive5_ODPerformanceLevels_Get
+@ stub ADL2_Overdrive5_ODPerformanceLevels_Set
+@ stub ADL2_Overdrive5_PowerControlAbsValue_Caps
+@ stub ADL2_Overdrive5_PowerControlAbsValue_Get
+@ stub ADL2_Overdrive5_PowerControlAbsValue_Set
+@ stub ADL2_Overdrive5_PowerControlInfo_Get
+@ stub ADL2_Overdrive5_PowerControl_Caps
+@ stub ADL2_Overdrive5_PowerControl_Get
+@ stub ADL2_Overdrive5_PowerControl_Set
+@ stub ADL2_Overdrive5_Temperature_Get
+@ stub ADL2_Overdrive5_ThermalDevices_Enum
+@ stub ADL2_Overdrive6_AdvancedFan_Caps
+@ stub ADL2_Overdrive6_CapabilitiesEx_Get
+@ stub ADL2_Overdrive6_Capabilities_Get
+@ stub ADL2_Overdrive6_ControlI2C
+@ stub ADL2_Overdrive6_CurrentPower_Get
+@ stub ADL2_Overdrive6_CurrentStatus_Get
+@ stub ADL2_Overdrive6_FanPWMLimitData_Get
+@ stub ADL2_Overdrive6_FanPWMLimitData_Set
+@ stub ADL2_Overdrive6_FanPWMLimitRangeInfo_Get
+@ stub ADL2_Overdrive6_FanSpeed_Get
+@ stub ADL2_Overdrive6_FanSpeed_Reset
+@ stub ADL2_Overdrive6_FanSpeed_Set
+@ stub ADL2_Overdrive6_FuzzyController_Caps
+@ stub ADL2_Overdrive6_MaxClockAdjust_Get
+@ stub ADL2_Overdrive6_PowerControlInfo_Get
+@ stub ADL2_Overdrive6_PowerControlInfo_Get_X2
+@ stub ADL2_Overdrive6_PowerControl_Caps
+@ stub ADL2_Overdrive6_PowerControl_Get
+@ stub ADL2_Overdrive6_PowerControl_Set
+@ stub ADL2_Overdrive6_StateEx_Get
+@ stub ADL2_Overdrive6_StateEx_Set
+@ stub ADL2_Overdrive6_StateInfo_Get
+@ stub ADL2_Overdrive6_State_Reset
+@ stub ADL2_Overdrive6_State_Set
+@ stub ADL2_Overdrive6_TargetTemperatureData_Get
+@ stub ADL2_Overdrive6_TargetTemperatureData_Set
+@ stub ADL2_Overdrive6_TargetTemperatureRangeInfo_Get
+@ stub ADL2_Overdrive6_TemperatureEx_Get
+@ stub ADL2_Overdrive6_Temperature_Get
+@ stub ADL2_Overdrive6_ThermalController_Caps
+@ stub ADL2_Overdrive6_ThermalLimitUnlock_Get
+@ stub ADL2_Overdrive6_ThermalLimitUnlock_Set
+@ stub ADL2_Overdrive6_VoltageControlInfo_Get
+@ stub ADL2_Overdrive6_VoltageControl_Get
+@ stub ADL2_Overdrive6_VoltageControl_Set
+@ stub ADL2_Overdrive8_Current_SettingX2_Get
+@ stub ADL2_Overdrive8_Current_SettingX3_Get
+@ stub ADL2_Overdrive8_Current_Setting_Get
+@ stub ADL2_Overdrive8_Init_SettingX2_Get
+@ stub ADL2_Overdrive8_Init_Setting_Get
+@ stub ADL2_Overdrive8_PMLogSenorRange_Caps
+@ stub ADL2_Overdrive8_PMLogSenorType_Support_Get
+@ stub ADL2_Overdrive8_PMLog_ShareMemory_Read
+@ stub ADL2_Overdrive8_PMLog_ShareMemory_Start
+@ stub ADL2_Overdrive8_PMLog_ShareMemory_Stop
+@ stub ADL2_Overdrive8_PMLog_ShareMemory_Support
+@ stub ADL2_Overdrive8_Setting_Set
+@ stub ADL2_OverdriveN_AutoWattman_Caps
+@ stub ADL2_OverdriveN_AutoWattman_Get
+@ stub ADL2_OverdriveN_AutoWattman_Set
+@ stub ADL2_OverdriveN_CapabilitiesX2_Get
+@ stub ADL2_OverdriveN_Capabilities_Get
+@ stub ADL2_OverdriveN_CountOfEvents_Get
+@ stub ADL2_OverdriveN_FanControl_Get
+@ stub ADL2_OverdriveN_FanControl_Set
+@ stub ADL2_OverdriveN_MemoryClocksX2_Get
+@ stub ADL2_OverdriveN_MemoryClocksX2_Set
+@ stub ADL2_OverdriveN_MemoryClocks_Get
+@ stub ADL2_OverdriveN_MemoryClocks_Set
+@ stub ADL2_OverdriveN_MemoryTimingLevel_Get
+@ stub ADL2_OverdriveN_MemoryTimingLevel_Set
+@ stub ADL2_OverdriveN_PerformanceStatus_Get
+@ stub ADL2_OverdriveN_PowerLimit_Get
+@ stub ADL2_OverdriveN_PowerLimit_Set
+@ stub ADL2_OverdriveN_SCLKAutoOverClock_Get
+@ stub ADL2_OverdriveN_SCLKAutoOverClock_Set
+@ stub ADL2_OverdriveN_SettingsExt_Get
+@ stub ADL2_OverdriveN_SettingsExt_Set
+@ stub ADL2_OverdriveN_SystemClocksX2_Get
+@ stub ADL2_OverdriveN_SystemClocksX2_Set
+@ stub ADL2_OverdriveN_SystemClocks_Get
+@ stub ADL2_OverdriveN_SystemClocks_Set
+@ stub ADL2_OverdriveN_Temperature_Get
+@ stub ADL2_OverdriveN_Test_Set
+@ stub ADL2_OverdriveN_ThrottleNotification_Get
+@ stub ADL2_OverdriveN_ZeroRPMFan_Get
+@ stub ADL2_OverdriveN_ZeroRPMFan_Set
+@ stdcall ADL2_Overdrive_Caps(ptr long ptr ptr ptr)
+@ stub ADL2_PPLogSettings_Get
+@ stub ADL2_PPLogSettings_Set
+@ stub ADL2_PPW_Caps
+@ stub ADL2_PPW_Status_Get
+@ stub ADL2_PPW_Status_Set
+@ stub ADL2_PageMigration_Settings_Get
+@ stub ADL2_PageMigration_Settings_Set
+@ stub ADL2_PerGPU_GDEvent_Register
+@ stub ADL2_PerGPU_GDEvent_UnRegister
+@ stub ADL2_PerfTuning_Status_Get
+@ stub ADL2_PerfTuning_Status_Set
+@ stub ADL2_PerformanceTuning_Caps
+@ stub ADL2_PowerStates_Get
+@ stub ADL2_PowerXpress_AncillaryDevices_Get
+@ stub ADL2_PowerXpress_Config_Caps
+@ stub ADL2_PowerXpress_Configuration_Get
+@ stub ADL2_PowerXpress_ExtendedBatteryMode_Caps
+@ stub ADL2_PowerXpress_ExtendedBatteryMode_Get
+@ stub ADL2_PowerXpress_ExtendedBatteryMode_Set
+@ stub ADL2_PowerXpress_LongIdleDetect_Get
+@ stub ADL2_PowerXpress_LongIdleDetect_Set
+@ stub ADL2_PowerXpress_PowerControlMode_Get
+@ stub ADL2_PowerXpress_PowerControlMode_Set
+@ stub ADL2_PowerXpress_Scheme_Get
+@ stub ADL2_PowerXpress_Scheme_Set
+@ stub ADL2_RIS_Settings_Get
+@ stub ADL2_RIS_Settings_Set
+@ stub ADL2_RegisterEvent
+@ stub ADL2_RegisterEventX2
+@ stub ADL2_Remap
+@ stub ADL2_RemoteDisplay_Destroy
+@ stub ADL2_RemoteDisplay_Display_Acquire
+@ stub ADL2_RemoteDisplay_Display_Release
+@ stub ADL2_RemoteDisplay_Display_Release_All
+@ stub ADL2_RemoteDisplay_Hdcp20_Create
+@ stub ADL2_RemoteDisplay_Hdcp20_Destroy
+@ stub ADL2_RemoteDisplay_Hdcp20_Notify
+@ stub ADL2_RemoteDisplay_Hdcp20_Process
+@ stub ADL2_RemoteDisplay_IEPort_Set
+@ stub ADL2_RemoteDisplay_Initialize
+@ stub ADL2_RemoteDisplay_Nofitiation_Register
+@ stub ADL2_RemoteDisplay_Notification_UnRegister
+@ stub ADL2_RemoteDisplay_Support_Caps
+@ stub ADL2_RemoteDisplay_VirtualWirelessAdapter_InUse_Get
+@ stub ADL2_RemoteDisplay_VirtualWirelessAdapter_Info_Get
+@ stub ADL2_RemoteDisplay_VirtualWirelessAdapter_RadioState_Get
+@ stub ADL2_RemoteDisplay_VirtualWirelessAdapter_WPSSetting_Change
+@ stub ADL2_RemoteDisplay_VirtualWirelessAdapter_WPSSetting_Get
+@ stub ADL2_RemoteDisplay_WFDDeviceInfo_Get
+@ stub ADL2_RemoteDisplay_WFDDeviceName_Change
+@ stub ADL2_RemoteDisplay_WFDDevice_StatusInfo_Get
+@ stub ADL2_RemoteDisplay_WFDDiscover_Start
+@ stub ADL2_RemoteDisplay_WFDDiscover_Stop
+@ stub ADL2_RemoteDisplay_WFDLink_Connect
+@ stub ADL2_RemoteDisplay_WFDLink_Creation_Accept
+@ stub ADL2_RemoteDisplay_WFDLink_Disconnect
+@ stub ADL2_RemoteDisplay_WFDLink_WPS_Process
+@ stub ADL2_RemoteDisplay_WFDWDSPSettings_Set
+@ stub ADL2_RemoteDisplay_WirelessDisplayEnableDisable_Commit
+@ stub ADL2_RemotePlay_ControlFlags_Set
+@ stub ADL2_ScreenPoint_AudioMappingInfo_Get
+@ stub ADL2_Send
+@ stub ADL2_SendX2
+@ stub ADL2_Stereo3D_2DPackedFormat_Set
+@ stub ADL2_Stereo3D_3DCursorOffset_Get
+@ stub ADL2_Stereo3D_3DCursorOffset_Set
+@ stub ADL2_Stereo3D_CurrentFormat_Get
+@ stub ADL2_Stereo3D_Info_Get
+@ stub ADL2_Stereo3D_Modes_Get
+@ stub ADL2_SwitchableGraphics_Applications_Get
+@ stub ADL2_TV_Standard_Get
+@ stub ADL2_TV_Standard_Set
+@ stub ADL2_TurboSyncSupport_Get
+@ stub ADL2_UnRegisterEvent
+@ stub ADL2_UnRegisterEventX2
+@ stub ADL2_User_Settings_Notify
+@ stub ADL2_WS_Overdrive_Caps
+@ stub ADL2_Win_IsHybridAI
+@ stub ADL2_Workstation_8BitGrayscale_Get
+@ stub ADL2_Workstation_8BitGrayscale_Set
+@ stub ADL2_Workstation_AdapterNumOfGLSyncConnectors_Get
+@ stub ADL2_Workstation_Caps
+@ stub ADL2_Workstation_DeepBitDepthX2_Get
+@ stub ADL2_Workstation_DeepBitDepthX2_Set
+@ stub ADL2_Workstation_DeepBitDepth_Get
+@ stub ADL2_Workstation_DeepBitDepth_Set
+@ stub ADL2_Workstation_DisplayGLSyncMode_Get
+@ stub ADL2_Workstation_DisplayGLSyncMode_Set
+@ stub ADL2_Workstation_DisplayGenlockCapable_Get
+@ stub ADL2_Workstation_ECCData_Get
+@ stub ADL2_Workstation_ECCX2_Get
+@ stub ADL2_Workstation_ECC_Caps
+@ stub ADL2_Workstation_ECC_Get
+@ stub ADL2_Workstation_ECC_Set
+@ stub ADL2_Workstation_GLSyncCounters_Get
+@ stub ADL2_Workstation_GLSyncGenlockConfiguration_Get
+@ stub ADL2_Workstation_GLSyncGenlockConfiguration_Set
+@ stub ADL2_Workstation_GLSyncModuleDetect_Get
+@ stub ADL2_Workstation_GLSyncModuleInfo_Get
+@ stub ADL2_Workstation_GLSyncPortState_Get
+@ stub ADL2_Workstation_GLSyncPortState_Set
+@ stub ADL2_Workstation_GLSyncSupportedTopology_Get
+@ stub ADL2_Workstation_GlobalEDIDPersistence_Get
+@ stub ADL2_Workstation_GlobalEDIDPersistence_Set
+@ stub ADL2_Workstation_LoadBalancing_Caps
+@ stub ADL2_Workstation_LoadBalancing_Get
+@ stub ADL2_Workstation_LoadBalancing_Set
+@ stub ADL2_Workstation_RAS_ErrorCounts_Get
+@ stub ADL2_Workstation_RAS_ErrorCounts_Reset
+@ stub ADL2_Workstation_SDISegmentList_Get
+@ stub ADL2_Workstation_SDI_Caps
+@ stub ADL2_Workstation_SDI_Get
+@ stub ADL2_Workstation_SDI_Set
+@ stub ADL2_Workstation_Stereo_Get
+@ stub ADL2_Workstation_Stereo_Set
+@ stub ADL2_Workstation_UnsupportedDisplayModes_Enable
+@ stub ADL_ADC_CurrentProfileFromDrv_Get
+@ stub ADL_ADC_Display_AdapterDeviceProfileEx_Get
+@ stub ADL_ADC_DrvDataToProfile_Copy
+@ stub ADL_ADC_FindClosestMode_Get
+@ stub ADL_ADC_IsDevModeEqual_Get
+@ stub ADL_ADC_Profile_Apply
+@ stub ADL_APO_AudioDelayAdjustmentInfo_Get
+@ stub ADL_APO_AudioDelay_Restore
+@ stub ADL_APO_AudioDelay_Set
+@ stub ADL_AdapterLimitation_Caps
+@ stub ADL_AdapterX2_Caps
+@ stdcall ADL_Adapter_ASICFamilyType_Get(long ptr ptr)
+@ stub ADL_Adapter_ASICInfo_Get
+@ stub ADL_Adapter_Accessibility_Get
+@ stub ADL_Adapter_Active_Get
+@ stub ADL_Adapter_Active_Set
+@ stub ADL_Adapter_Active_SetPrefer
+@ stub ADL_Adapter_AdapterInfoX2_Get
+@ stdcall ADL_Adapter_AdapterInfo_Get(ptr long)
+@ stub ADL_Adapter_AdapterList_Disable
+@ stub ADL_Adapter_Aspects_Get
+@ stub ADL_Adapter_AudioChannelSplitConfiguration_Get
+@ stub ADL_Adapter_AudioChannelSplit_Disable
+@ stub ADL_Adapter_AudioChannelSplit_Enable
+@ stub ADL_Adapter_BigSw_Info_Get
+@ stub ADL_Adapter_BlackAndWhiteLevelSupport_Get
+@ stub ADL_Adapter_BlackAndWhiteLevel_Get
+@ stub ADL_Adapter_BlackAndWhiteLevel_Set
+@ stub ADL_Adapter_BoardLayout_Get
+@ stub ADL_Adapter_Caps
+@ stub ADL_Adapter_ChipSetInfo_Get
+@ stub ADL_Adapter_ConfigMemory_Cap
+@ stub ADL_Adapter_ConfigMemory_Get
+@ stub ADL_Adapter_ConfigureState_Get
+@ stub ADL_Adapter_ConnectionData_Get
+@ stub ADL_Adapter_ConnectionData_Remove
+@ stub ADL_Adapter_ConnectionData_Set
+@ stub ADL_Adapter_ConnectionState_Get
+@ stub ADL_Adapter_CrossDisplayPlatformInfo_Get
+@ stub ADL_Adapter_CrossdisplayAdapterRole_Caps
+@ stub ADL_Adapter_CrossdisplayInfoX2_Set
+@ stub ADL_Adapter_CrossdisplayInfo_Get
+@ stub ADL_Adapter_CrossdisplayInfo_Set
+@ stub ADL_Adapter_CrossfireX2_Get
+@ stdcall ADL_Adapter_Crossfire_Caps(long ptr ptr ptr)
+@ stdcall ADL_Adapter_Crossfire_Get(long ptr ptr)
+@ stub ADL_Adapter_Crossfire_Set
+@ stub ADL_Adapter_DefaultAudioChannelTable_Load
+@ stub ADL_Adapter_DisplayAudioEndpoint_Enable
+@ stub ADL_Adapter_DisplayAudioEndpoint_Mute
+@ stub ADL_Adapter_DisplayAudioInfo_Get
+@ stub ADL_Adapter_DisplayGTCCaps_Get
+@ stub ADL_Adapter_Display_Caps
+@ stub ADL_Adapter_DriverSettings_Get
+@ stub ADL_Adapter_DriverSettings_Set
+@ stub ADL_Adapter_EDIDManagement_Caps
+@ stub ADL_Adapter_EmulationMode_Set
+@ stub ADL_Adapter_ExtInfo_Get
+@ stub ADL_Adapter_Gamma_Get
+@ stub ADL_Adapter_Gamma_Set
+@ stub ADL_Adapter_ID_Get
+@ stub ADL_Adapter_LocalDisplayConfig_Get
+@ stub ADL_Adapter_LocalDisplayConfig_Set
+@ stub ADL_Adapter_LocalDisplayState_Get
+@ stub ADL_Adapter_MaxCursorSize_Get
+@ stub ADL_Adapter_MemoryInfo2_Get
+@ stdcall ADL_Adapter_MemoryInfo_Get(long ptr)
+@ stub ADL_Adapter_MirabilisSupport_Get
+@ stub ADL_Adapter_ModeSwitch
+@ stub ADL_Adapter_ModeTimingOverride_Caps
+@ stub ADL_Adapter_Modes_ReEnumerate
+@ stub ADL_Adapter_NumberOfActivatableSources_Get
+@ stdcall ADL_Adapter_NumberOfAdapters_Get(ptr)
+@ stdcall ADL_Adapter_ObservedClockInfo_Get(long ptr ptr)
+@ stdcall ADL_Adapter_ObservedGameClockInfo_Get(ptr long ptr ptr ptr ptr)
+@ stdcall ADL_Adapter_Primary_Get(long)
+@ stub ADL_Adapter_Primary_Set
+@ stub ADL_Adapter_RegValueInt_Get
+@ stub ADL_Adapter_RegValueInt_Set
+@ stub ADL_Adapter_RegValueString_Get
+@ stub ADL_Adapter_RegValueString_Set
+@ stub ADL_Adapter_SWInfo_Get
+@ stub ADL_Adapter_Speed_Caps
+@ stub ADL_Adapter_Speed_Get
+@ stub ADL_Adapter_Speed_Set
+@ stub ADL_Adapter_SupportedConnections_Get
+@ stub ADL_Adapter_Tear_Free_Cap
+@ stub ADL_Adapter_VariBrightEnable_Set
+@ stub ADL_Adapter_VariBrightLevel_Get
+@ stub ADL_Adapter_VariBrightLevel_Set
+@ stub ADL_Adapter_VariBright_Caps
+@ stub ADL_Adapter_VideoBiosInfo_Get
+@ stub ADL_Adapter_VideoTheaterModeInfo_Get
+@ stub ADL_Adapter_VideoTheaterModeInfo_Set
+@ stub ADL_ApplicationProfiles_Applications_Get
+@ stub ADL_ApplicationProfiles_ConvertToCompact
+@ stub ADL_ApplicationProfiles_DriverAreaPrivacy_Get
+@ stub ADL_ApplicationProfiles_GetCustomization
+@ stub ADL_ApplicationProfiles_HitListsX2_Get
+@ stub ADL_ApplicationProfiles_HitLists_Get
+@ stub ADL_ApplicationProfiles_ProfileApplicationX2_Assign
+@ stub ADL_ApplicationProfiles_ProfileApplication_Assign
+@ stub ADL_ApplicationProfiles_ProfileOfAnApplicationX2_Search
+@ stub ADL_ApplicationProfiles_ProfileOfAnApplication_InMemorySearch
+@ stub ADL_ApplicationProfiles_ProfileOfAnApplication_Search
+@ stub ADL_ApplicationProfiles_Profile_Create
+@ stub ADL_ApplicationProfiles_Profile_Exist
+@ stub ADL_ApplicationProfiles_Profile_Remove
+@ stub ADL_ApplicationProfiles_PropertyType_Get
+@ stub ADL_ApplicationProfiles_Release_Get
+@ stub ADL_ApplicationProfiles_RemoveApplication
+@ stub ADL_ApplicationProfiles_StatusInfo_Get
+@ stub ADL_ApplicationProfiles_System_Reload
+@ stub ADL_ApplicationProfiles_User_Load
+@ stub ADL_ApplicationProfiles_User_Unload
+@ stub ADL_Audio_CurrentSampleRate_Get
+@ stub ADL_CDS_UnsafeMode_Set
+@ stub ADL_CV_DongleSettings_Get
+@ stub ADL_CV_DongleSettings_Reset
+@ stub ADL_CV_DongleSettings_Set
+@ stub ADL_DFP_AllowOnlyCETimings_Get
+@ stub ADL_DFP_AllowOnlyCETimings_Set
+@ stub ADL_DFP_BaseAudioSupport_Get
+@ stub ADL_DFP_GPUScalingEnable_Get
+@ stub ADL_DFP_GPUScalingEnable_Set
+@ stub ADL_DFP_HDMISupport_Get
+@ stub ADL_DFP_MVPUAnalogSupport_Get
+@ stub ADL_DFP_PixelFormat_Caps
+@ stub ADL_DFP_PixelFormat_Get
+@ stub ADL_DFP_PixelFormat_Set
+@ stub ADL_DisplayScaling_Set
+@ stub ADL_Display_AdapterID_Get
+@ stub ADL_Display_AdjustCaps_Get
+@ stub ADL_Display_AdjustmentCoherent_Get
+@ stub ADL_Display_AdjustmentCoherent_Set
+@ stub ADL_Display_AudioMappingInfo_Get
+@ stub ADL_Display_AvivoColor_Get
+@ stub ADL_Display_AvivoCurrentColor_Set
+@ stub ADL_Display_AvivoDefaultColor_Set
+@ stub ADL_Display_BackLight_Get
+@ stub ADL_Display_BackLight_Set
+@ stub ADL_Display_BezelOffsetSteppingSize_Get
+@ stub ADL_Display_BezelOffset_Set
+@ stub ADL_Display_BezelSupported_Validate
+@ stub ADL_Display_Capabilities_Get
+@ stub ADL_Display_ColorCaps_Get
+@ stub ADL_Display_ColorDepth_Get
+@ stub ADL_Display_ColorDepth_Set
+@ stub ADL_Display_ColorTemperatureSource_Get
+@ stub ADL_Display_ColorTemperatureSource_Set
+@ stub ADL_Display_Color_Get
+@ stub ADL_Display_Color_Set
+@ stub ADL_Display_ConnectedDisplays_Get
+@ stub ADL_Display_ContainerID_Get
+@ stub ADL_Display_ControllerOverlayAdjustmentCaps_Get
+@ stub ADL_Display_ControllerOverlayAdjustmentData_Get
+@ stub ADL_Display_ControllerOverlayAdjustmentData_Set
+@ stub ADL_Display_CurrentPixelClock_Get
+@ stub ADL_Display_CustomizedModeListNum_Get
+@ stub ADL_Display_CustomizedModeList_Get
+@ stub ADL_Display_CustomizedMode_Add
+@ stub ADL_Display_CustomizedMode_Delete
+@ stub ADL_Display_CustomizedMode_Validate
+@ stub ADL_Display_DCE_Get
+@ stub ADL_Display_DCE_Set
+@ stub ADL_Display_DDCBlockAccess_Get
+@ stub ADL_Display_DDCInfo2_Get
+@ stub ADL_Display_DDCInfo_Get
+@ stub ADL_Display_Deflicker_Get
+@ stub ADL_Display_Deflicker_Set
+@ stub ADL_Display_DeviceConfig_Get
+@ stub ADL_Display_DisplayContent_Cap
+@ stub ADL_Display_DisplayContent_Get
+@ stub ADL_Display_DisplayContent_Set
+@ stdcall ADL_Display_DisplayInfo_Get(long long ptr long)
+@ stdcall ADL_Display_DisplayMapConfig_Get(long ptr ptr ptr ptr long)
+@ stub ADL_Display_DisplayMapConfig_PossibleAddAndRemove
+@ stub ADL_Display_DisplayMapConfig_Set
+@ stub ADL_Display_DisplayMapConfig_Validate
+@ stub ADL_Display_DitherState_Get
+@ stub ADL_Display_DitherState_Set
+@ stub ADL_Display_Downscaling_Caps
+@ stub ADL_Display_DpMstInfo_Get
+@ stdcall ADL_Display_EdidData_Get(long long ptr)
+@ stub ADL_Display_EdidData_Set
+@ stub ADL_Display_EnumDisplays_Get
+@ stub ADL_Display_FilterSVideo_Get
+@ stub ADL_Display_FilterSVideo_Set
+@ stub ADL_Display_ForcibleDisplay_Get
+@ stub ADL_Display_ForcibleDisplay_Set
+@ stub ADL_Display_FormatsOverride_Get
+@ stub ADL_Display_FormatsOverride_Set
+@ stub ADL_Display_FreeSyncState_Get
+@ stub ADL_Display_FreeSyncState_Set
+@ stub ADL_Display_FreeSync_Cap
+@ stub ADL_Display_GamutMapping_Get
+@ stub ADL_Display_GamutMapping_Reset
+@ stub ADL_Display_GamutMapping_Set
+@ stub ADL_Display_Gamut_Caps
+@ stub ADL_Display_Gamut_Get
+@ stub ADL_Display_Gamut_Set
+@ stub ADL_Display_ImageExpansion_Get
+@ stub ADL_Display_ImageExpansion_Set
+@ stub ADL_Display_InfoPacket_Get
+@ stub ADL_Display_InfoPacket_Set
+@ stub ADL_Display_LCDRefreshRateCapability_Get
+@ stub ADL_Display_LCDRefreshRateOptions_Get
+@ stub ADL_Display_LCDRefreshRateOptions_Set
+@ stub ADL_Display_LCDRefreshRate_Get
+@ stub ADL_Display_LCDRefreshRate_Set
+@ stub ADL_Display_Limits_Get
+@ stub ADL_Display_MVPUCaps_Get
+@ stub ADL_Display_MVPUStatus_Get
+@ stub ADL_Display_ModeTimingOverrideInfo_Get
+@ stub ADL_Display_ModeTimingOverrideListX2_Get
+@ stub ADL_Display_ModeTimingOverrideList_Get
+@ stub ADL_Display_ModeTimingOverrideX2_Get
+@ stub ADL_Display_ModeTimingOverride_Delete
+@ stub ADL_Display_ModeTimingOverride_Get
+@ stub ADL_Display_ModeTimingOverride_Set
+@ stub ADL_Display_Modes_Get
+@ stub ADL_Display_Modes_Set
+@ stub ADL_Display_MonitorPowerState_Set
+@ stub ADL_Display_NativeAUXChannel_Access
+@ stub ADL_Display_NeedWorkaroundFor5Clone_Get
+@ stub ADL_Display_NumberOfDisplays_Get
+@ stub ADL_Display_ODClockConfig_Set
+@ stub ADL_Display_ODClockInfo_Get
+@ stub ADL_Display_Overlap_Set
+@ stub ADL_Display_Overscan_Get
+@ stub ADL_Display_Overscan_Set
+@ stub ADL_Display_PixelClockAllowableRange_Set
+@ stub ADL_Display_PixelClockCaps_Get
+@ stub ADL_Display_PixelFormat_Get
+@ stub ADL_Display_PixelFormat_Set
+@ stub ADL_Display_Position_Get
+@ stub ADL_Display_Position_Set
+@ stub ADL_Display_PossibleMapping_Get
+@ stub ADL_Display_PossibleMode_Get
+@ stub ADL_Display_PowerXpressActiveGPU_Get
+@ stub ADL_Display_PowerXpressActiveGPU_Set
+@ stub ADL_Display_PowerXpressActvieGPUR2_Get
+@ stub ADL_Display_PowerXpressVersion_Get
+@ stub ADL_Display_PowerXpress_AutoSwitchConfig_Get
+@ stub ADL_Display_PowerXpress_AutoSwitchConfig_Set
+@ stub ADL_Display_PreservedAspectRatio_Get
+@ stub ADL_Display_PreservedAspectRatio_Set
+@ stub ADL_Display_Property_Get
+@ stub ADL_Display_Property_Set
+@ stub ADL_Display_RcDisplayAdjustment
+@ stub ADL_Display_ReGammaCoefficients_Get
+@ stub ADL_Display_ReGammaCoefficients_Set
+@ stub ADL_Display_ReducedBlanking_Get
+@ stub ADL_Display_ReducedBlanking_Set
+@ stub ADL_Display_RegammaR1_Get
+@ stub ADL_Display_RegammaR1_Set
+@ stub ADL_Display_Regamma_Get
+@ stub ADL_Display_Regamma_Set
+@ stub ADL_Display_SLSGrid_Caps
+@ stub ADL_Display_SLSMapConfigX2_Get
+@ stub ADL_Display_SLSMapConfig_Create
+@ stub ADL_Display_SLSMapConfig_Delete
+@ stub ADL_Display_SLSMapConfig_Get
+@ stub ADL_Display_SLSMapConfig_Rearrange
+@ stub ADL_Display_SLSMapConfig_SetState
+@ stub ADL_Display_SLSMapIndexList_Get
+@ stub ADL_Display_SLSMapIndex_Get
+@ stub ADL_Display_SLSMiddleMode_Get
+@ stub ADL_Display_SLSMiddleMode_Set
+@ stub ADL_Display_SLSRecords_Get
+@ stub ADL_Display_Sharpness_Caps
+@ stub ADL_Display_Sharpness_Get
+@ stub ADL_Display_Sharpness_Info_Get
+@ stub ADL_Display_Sharpness_Set
+@ stub ADL_Display_Size_Get
+@ stub ADL_Display_Size_Set
+@ stub ADL_Display_SourceContentAttribute_Get
+@ stub ADL_Display_SourceContentAttribute_Set
+@ stub ADL_Display_SplitDisplay_Caps
+@ stub ADL_Display_SplitDisplay_Get
+@ stub ADL_Display_SplitDisplay_RestoreDesktopConfiguration
+@ stub ADL_Display_SplitDisplay_Set
+@ stub ADL_Display_SupportedColorDepth_Get
+@ stub ADL_Display_SupportedPixelFormat_Get
+@ stub ADL_Display_SwitchingCapability_Get
+@ stub ADL_Display_TVCaps_Get
+@ stub ADL_Display_TargetTiming_Get
+@ stub ADL_Display_UnderScan_Auto_Get
+@ stub ADL_Display_UnderScan_Auto_Set
+@ stub ADL_Display_Underscan_Get
+@ stub ADL_Display_Underscan_Set
+@ stub ADL_Display_Vector_Get
+@ stub ADL_Display_ViewPort_Cap
+@ stub ADL_Display_ViewPort_Get
+@ stub ADL_Display_ViewPort_Set
+@ stub ADL_Display_WriteAndReadI2C
+@ stub ADL_Display_WriteAndReadI2CLargePayload
+@ stub ADL_Display_WriteAndReadI2CRev_Get
+@ stub ADL_Flush_Driver_Data
+@ stdcall ADL_Graphics_Platform_Get(ptr)
+@ stdcall ADL_Graphics_Versions_Get(ptr)
+@ stub ADL_MMD_FeatureList_Get
+@ stub ADL_MMD_FeatureValuesX2_Get
+@ stub ADL_MMD_FeatureValuesX2_Set
+@ stub ADL_MMD_FeatureValues_Get
+@ stub ADL_MMD_FeatureValues_Set
+@ stub ADL_MMD_FeaturesX2_Caps
+@ stub ADL_MMD_Features_Caps
+@ stub ADL_MMD_VideoAdjustInfo_Get
+@ stub ADL_MMD_VideoAdjustInfo_Set
+@ stub ADL_MMD_VideoColor_Caps
+@ stub ADL_MMD_VideoColor_Get
+@ stub ADL_MMD_VideoColor_Set
+@ stub ADL_MMD_Video_Caps
+@ stub ADL_Main_ControlX2_Create
+@ stdcall ADL_Main_Control_Create(ptr long)
+@ stdcall ADL_Main_Control_Destroy()
+@ stub ADL_Main_Control_GetProcAddress
+@ stub ADL_Main_Control_IsFunctionValid
+@ stub ADL_Main_Control_Refresh
+@ stub ADL_Main_LogDebug_Set
+@ stub ADL_Main_LogError_Set
+@ stub ADL_Overdrive5_CurrentActivity_Get
+@ stub ADL_Overdrive5_FanSpeedInfo_Get
+@ stub ADL_Overdrive5_FanSpeedToDefault_Set
+@ stub ADL_Overdrive5_FanSpeed_Get
+@ stub ADL_Overdrive5_FanSpeed_Set
+@ stdcall ADL_Overdrive5_ODParameters_Get(long ptr)
+@ stub ADL_Overdrive5_ODPerformanceLevels_Get
+@ stub ADL_Overdrive5_ODPerformanceLevels_Set
+@ stub ADL_Overdrive5_PowerControlAbsValue_Caps
+@ stub ADL_Overdrive5_PowerControlAbsValue_Get
+@ stub ADL_Overdrive5_PowerControlAbsValue_Set
+@ stub ADL_Overdrive5_PowerControlInfo_Get
+@ stub ADL_Overdrive5_PowerControl_Caps
+@ stub ADL_Overdrive5_PowerControl_Get
+@ stub ADL_Overdrive5_PowerControl_Set
+@ stub ADL_Overdrive5_Temperature_Get
+@ stub ADL_Overdrive5_ThermalDevices_Enum
+@ stub ADL_Overdrive6_AdvancedFan_Caps
+@ stub ADL_Overdrive6_CapabilitiesEx_Get
+@ stub ADL_Overdrive6_Capabilities_Get
+@ stub ADL_Overdrive6_CurrentStatus_Get
+@ stub ADL_Overdrive6_FanPWMLimitData_Get
+@ stub ADL_Overdrive6_FanPWMLimitData_Set
+@ stub ADL_Overdrive6_FanPWMLimitRangeInfo_Get
+@ stub ADL_Overdrive6_FanSpeed_Get
+@ stub ADL_Overdrive6_FanSpeed_Reset
+@ stub ADL_Overdrive6_FanSpeed_Set
+@ stub ADL_Overdrive6_FuzzyController_Caps
+@ stub ADL_Overdrive6_MaxClockAdjust_Get
+@ stub ADL_Overdrive6_PowerControlInfo_Get
+@ stub ADL_Overdrive6_PowerControl_Caps
+@ stub ADL_Overdrive6_PowerControl_Get
+@ stub ADL_Overdrive6_PowerControl_Set
+@ stub ADL_Overdrive6_StateEx_Get
+@ stub ADL_Overdrive6_StateEx_Set
+@ stub ADL_Overdrive6_StateInfo_Get
+@ stub ADL_Overdrive6_State_Reset
+@ stub ADL_Overdrive6_State_Set
+@ stub ADL_Overdrive6_TargetTemperatureData_Get
+@ stub ADL_Overdrive6_TargetTemperatureData_Set
+@ stub ADL_Overdrive6_TargetTemperatureRangeInfo_Get
+@ stub ADL_Overdrive6_Temperature_Get
+@ stub ADL_Overdrive6_ThermalController_Caps
+@ stub ADL_Overdrive6_ThermalLimitUnlock_Get
+@ stub ADL_Overdrive6_ThermalLimitUnlock_Set
+@ stub ADL_Overdrive6_VoltageControlInfo_Get
+@ stub ADL_Overdrive6_VoltageControl_Get
+@ stub ADL_Overdrive6_VoltageControl_Set
+@ stub ADL_Overdrive_Caps
+@ stub ADL_PowerXpress_AncillaryDevices_Get
+@ stub ADL_PowerXpress_Config_Caps
+@ stub ADL_PowerXpress_ExtendedBatteryMode_Caps
+@ stub ADL_PowerXpress_ExtendedBatteryMode_Get
+@ stub ADL_PowerXpress_ExtendedBatteryMode_Set
+@ stub ADL_PowerXpress_LongIdleDetect_Get
+@ stub ADL_PowerXpress_LongIdleDetect_Set
+@ stub ADL_PowerXpress_PowerControlMode_Get
+@ stub ADL_PowerXpress_PowerControlMode_Set
+@ stub ADL_PowerXpress_Scheme_Get
+@ stub ADL_PowerXpress_Scheme_Set
+@ stub ADL_Remap
+@ stub ADL_RemoteDisplay_Destroy
+@ stub ADL_RemoteDisplay_Display_Acquire
+@ stub ADL_RemoteDisplay_Display_Release
+@ stub ADL_RemoteDisplay_Display_Release_All
+@ stub ADL_RemoteDisplay_Hdcp20_Create
+@ stub ADL_RemoteDisplay_Hdcp20_Destroy
+@ stub ADL_RemoteDisplay_Hdcp20_Notify
+@ stub ADL_RemoteDisplay_Hdcp20_Process
+@ stub ADL_RemoteDisplay_IEPort_Set
+@ stub ADL_RemoteDisplay_Initialize
+@ stub ADL_RemoteDisplay_Nofitiation_Register
+@ stub ADL_RemoteDisplay_Notification_UnRegister
+@ stub ADL_RemoteDisplay_Support_Caps
+@ stub ADL_RemoteDisplay_VirtualWirelessAdapter_InUse_Get
+@ stub ADL_RemoteDisplay_VirtualWirelessAdapter_Info_Get
+@ stub ADL_RemoteDisplay_VirtualWirelessAdapter_RadioState_Get
+@ stub ADL_RemoteDisplay_VirtualWirelessAdapter_WPSSetting_Change
+@ stub ADL_RemoteDisplay_VirtualWirelessAdapter_WPSSetting_Get
+@ stub ADL_RemoteDisplay_WFDDeviceInfo_Get
+@ stub ADL_RemoteDisplay_WFDDeviceName_Change
+@ stub ADL_RemoteDisplay_WFDDevice_StatusInfo_Get
+@ stub ADL_RemoteDisplay_WFDDiscover_Start
+@ stub ADL_RemoteDisplay_WFDDiscover_Stop
+@ stub ADL_RemoteDisplay_WFDLink_Connect
+@ stub ADL_RemoteDisplay_WFDLink_Creation_Accept
+@ stub ADL_RemoteDisplay_WFDLink_Disconnect
+@ stub ADL_RemoteDisplay_WFDLink_WPS_Process
+@ stub ADL_RemoteDisplay_WFDWDSPSettings_Set
+@ stub ADL_RemoteDisplay_WirelessDisplayEnableDisable_Commit
+@ stub ADL_ScreenPoint_AudioMappingInfo_Get
+@ stub ADL_Stereo3D_2DPackedFormat_Set
+@ stub ADL_Stereo3D_3DCursorOffset_Get
+@ stub ADL_Stereo3D_3DCursorOffset_Set
+@ stub ADL_Stereo3D_CurrentFormat_Get
+@ stub ADL_Stereo3D_Info_Get
+@ stub ADL_Stereo3D_Modes_Get
+@ stub ADL_TV_Standard_Get
+@ stub ADL_TV_Standard_Set
+@ stub ADL_Win_IsHybridAI
+@ stub ADL_Workstation_8BitGrayscale_Get
+@ stub ADL_Workstation_8BitGrayscale_Set
+@ stub ADL_Workstation_AdapterNumOfGLSyncConnectors_Get
+@ stub ADL_Workstation_Caps
+@ stub ADL_Workstation_DeepBitDepthX2_Get
+@ stub ADL_Workstation_DeepBitDepthX2_Set
+@ stub ADL_Workstation_DeepBitDepth_Get
+@ stub ADL_Workstation_DeepBitDepth_Set
+@ stub ADL_Workstation_DisplayGLSyncMode_Get
+@ stub ADL_Workstation_DisplayGLSyncMode_Set
+@ stub ADL_Workstation_DisplayGenlockCapable_Get
+@ stub ADL_Workstation_ECCData_Get
+@ stub ADL_Workstation_ECCX2_Get
+@ stub ADL_Workstation_ECC_Caps
+@ stub ADL_Workstation_ECC_Get
+@ stub ADL_Workstation_ECC_Set
+@ stub ADL_Workstation_GLSyncCounters_Get
+@ stub ADL_Workstation_GLSyncGenlockConfiguration_Get
+@ stub ADL_Workstation_GLSyncGenlockConfiguration_Set
+@ stub ADL_Workstation_GLSyncModuleDetect_Get
+@ stub ADL_Workstation_GLSyncModuleInfo_Get
+@ stub ADL_Workstation_GLSyncPortState_Get
+@ stub ADL_Workstation_GLSyncPortState_Set
+@ stub ADL_Workstation_GLSyncSupportedTopology_Get
+@ stub ADL_Workstation_GlobalEDIDPersistence_Get
+@ stub ADL_Workstation_GlobalEDIDPersistence_Set
+@ stub ADL_Workstation_LoadBalancing_Caps
+@ stub ADL_Workstation_LoadBalancing_Get
+@ stub ADL_Workstation_LoadBalancing_Set
+@ stub ADL_Workstation_RAS_Get_Error_Counts
+@ stub ADL_Workstation_RAS_Get_Features
+@ stub ADL_Workstation_RAS_Reset_Error_Counts
+@ stub ADL_Workstation_RAS_Set_Features
+@ stub ADL_Workstation_SDISegmentList_Get
+@ stub ADL_Workstation_SDI_Caps
+@ stub ADL_Workstation_SDI_Get
+@ stub ADL_Workstation_SDI_Set
+@ stub ADL_Workstation_Stereo_Get
+@ stub ADL_Workstation_Stereo_Set
+@ stub ADL_Workstation_UnsupportedDisplayModes_Enable
+@ stub AmdPowerXpressRequestHighPerformance
+@ stub Desktop_Detach
+@ stub Send
+@ stub SendX2
diff --git a/wine/dlls/atiadlxx/atiadlxx_main.c b/wine/dlls/atiadlxx/atiadlxx_main.c
new file mode 100644
index 000000000..9f8873876
--- /dev/null
+++ b/wine/dlls/atiadlxx/atiadlxx_main.c
@@ -0,0 +1,752 @@
+/* Headers: https://github.com/GPUOpen-LibrariesAndSDKs/display-library */
+#include <stdarg.h>
+#include <stdio.h>
+#include <stdlib.h>
+#define COBJMACROS
+#include "windef.h"
+#include "winbase.h"
+#include "winuser.h"
+#include "objbase.h"
+#include "initguid.h"
+#include "wine/debug.h"
+#include "dxgi.h"
+#define MAX_GPUS 64
+#define VENDOR_AMD 0x1002
+#define ADL_OK                            0
+#define ADL_ERR                          -1
+#define ADL_ERR_INVALID_PARAM            -3
+#define ADL_ERR_INVALID_ADL_IDX          -5
+#define ADL_ERR_NOT_SUPPORTED            -8
+#define ADL_ERR_NULL_POINTER             -9
+#define ADL_DISPLAY_DISPLAYINFO_DISPLAYCONNECTED            0x00000001
+#define ADL_DISPLAY_DISPLAYINFO_DISPLAYMAPPED               0x00000002
+#define ADL_DISPLAY_DISPLAYINFO_MASK 0x31fff
+#define ADL_ASIC_DISCRETE    (1 << 0)
+#define ADL_ASIC_MASK        0xAF
+enum ADLPlatForm
+    GRAPHICS_PLATFORM_DESKTOP  = 0,
+    GRAPHICS_PLATFORM_MOBILE   = 1
+};
+#define GRAPHICS_PLATFORM_UNKNOWN -1
+static IDXGIFactory *dxgi_factory;
+WINE_DEFAULT_DEBUG_CHANNEL(atiadlxx);
+BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
+    TRACE("(%p, %u, %p)\n", instance, reason, reserved);
+    switch (reason)
+    case DLL_PROCESS_ATTACH:
+        DisableThreadLibraryCalls(instance);
+        break;
+    return TRUE;
+typedef void *(CALLBACK *ADL_MAIN_MALLOC_CALLBACK)(int);
+typedef void *ADL_CONTEXT_HANDLE;
+ADL_MAIN_MALLOC_CALLBACK adl_malloc;
+#define ADL_MAX_PATH 256
+typedef struct ADLDDCInfo2 {
+} ADLDDCInfo2;
+typedef struct ADLFreeSyncCap {
+} ADLFreeSyncCap;
+typedef struct ADLVersionsInfo
+    char strDriverVer[ADL_MAX_PATH];
+    char strCatalystVersion[ADL_MAX_PATH];
+    char strCatalystWebLink[ADL_MAX_PATH];
+} ADLVersionsInfo, *LPADLVersionsInfo;
+typedef struct ADLVersionsInfoX2
+    char strDriverVer[ADL_MAX_PATH];
+    char strCatalystVersion[ADL_MAX_PATH];
+    char strCrimsonVersion[ADL_MAX_PATH];
+    char strCatalystWebLink[ADL_MAX_PATH];
+} ADLVersionsInfoX2, *LPADLVersionsInfoX2;
+typedef struct ADLAdapterInfo {
+    int iSize;
+    int iAdapterIndex;
+    char strUDID[ADL_MAX_PATH];
+    int iBusNumber;
+    int iDeviceNumber;
+    int iFunctionNumber;
+    int iVendorID;
+    char strAdapterName[ADL_MAX_PATH];
+    char strDisplayName[ADL_MAX_PATH];
+    int iPresent;
+    int iExist;
+    char strDriverPath[ADL_MAX_PATH];
+    char strDriverPathExt[ADL_MAX_PATH];
+    char strPNPString[ADL_MAX_PATH];
+    int iOSDisplayIndex;
+} ADLAdapterInfo, *LPADLAdapterInfo;
+typedef struct ADLAdapterInfoX2 { //Matches ADLAdapterInfo until iInfoMask
+    int iSize;
+    int iAdapterIndex;
+    char strUDID[ADL_MAX_PATH];
+    int iBusNumber;
+    int iDeviceNumber;
+    int iFunctionNumber;
+    int iVendorID;
+    char strAdapterName[ADL_MAX_PATH];
+    char strDisplayName[ADL_MAX_PATH];
+    int iPresent;
+    int iExist;
+    char strDriverPath[ADL_MAX_PATH];
+    char strDriverPathExt[ADL_MAX_PATH];
+    char strPNPString[ADL_MAX_PATH];
+    int iOSDisplayIndex;
+    int iInfoMask;
+    int iInfoValue;
+} ADLAdapterInfoX2, *LPADLAdapterInfoX2;
+typedef struct ADLDisplayID
+    int iDisplayLogicalIndex;
+    int iDisplayPhysicalIndex;
+    int iDisplayLogicalAdapterIndex;
+    int iDisplayPhysicalAdapterIndex;
+} ADLDisplayID, *LPADLDisplayID;
+typedef struct ADLDisplayInfo
+    ADLDisplayID displayID;
+    int  iDisplayControllerIndex;
+    char strDisplayName[ADL_MAX_PATH];
+    char strDisplayManufacturerName[ADL_MAX_PATH];
+    int  iDisplayType;
+    int  iDisplayOutputType;
+    int  iDisplayConnector;
+    int  iDisplayInfoMask;
+    int  iDisplayInfoValue;
+} ADLDisplayInfo, *LPADLDisplayInfo;
+typedef struct ADLCrossfireComb
+    int iNumLinkAdapter;
+    int iAdaptLink[3];
+} ADLCrossfireComb;
+typedef struct ADLCrossfireInfo
+{
+  int iErrorCode;
+  int iState;
+  int iSupported;
+} ADLCrossfireInfo;
+typedef struct ADLMemoryInfo
+{
+    long long iMemorySize;
+    char strMemoryType[ADL_MAX_PATH];
+    long long iMemoryBandwidth;
+} ADLMemoryInfo, *LPADLMemoryInfo;
+typedef struct ADLMemoryInfo2
+{
+    long long iHyperMemorySize;
+    long long iInvisibleMemorySize;
+    long long iMemoryBandwidth;
+    long long iMemorySize;
+    long long iVisibleMemorySize;
+    char strMemoryType[ADL_MAX_PATH];
+} ADLMemoryInfo2, *LPADLMemoryInfo2;
+typedef struct ADLDisplayTarget
+    ADLDisplayID displayID;
+    int iDisplayMapIndex;
+    int iDisplayTargetMask;
+    int iDisplayTargetValue;
+} ADLDisplayTarget, *LPADLDisplayTarget;
+typedef struct ADLMode
+    int iAdapterIndex;
+    ADLDisplayID displayID;
+    int iXPos;
+    int iYPos;
+    int iXRes;
+    int iYRes;
+    int iColourDepth;
+    float fRefreshRate;
+    int iOrientation;
+    int iModeFlag;
+    int iModeMask;
+    int iModeValue;
+} ADLMode, *LPADLMode;
+typedef struct ADLDisplayMap
+{
+    int iDisplayMapIndex;
+    ADLMode displayMode;
+    int iNumDisplayTarget;
+    int iFirstDisplayTargetArrayIndex;
+    int iDisplayMapMask;
+    int iDisplayMapValue;
+} ADLDisplayMap, *LPADLDisplayMap;
+typedef struct ADLGraphicInfoCore
+{
+    union
+        int iNumPEsPerCU;
+        int iNumPEsPerWGP;
+    };
+    union
+    {
+        int iNumCUs;
+        int iNumWGPs;
+    };
+    int iGCGen;
+    int iNumROPs;
+    int iNumSIMDs;
+    int iReserved[11];
+} ADLGraphicInfoCore, *LPADLGraphicInfoCore;
+typedef struct ADLODParameterRange
+   int iMin;
+   int iMax;
+   int iStep;
+} ADLODParameterRange;
+  
+typedef struct ADLODParameters
+   int iSize;
+   int iNumberOfPerformanceLevels;
+   int iActivityReportingSupported;
+   int iDiscretePerformanceLevels;
+   int iReserved;
+   ADLODParameterRange sEngineClock;
+   ADLODParameterRange sMemoryClock;
+   ADLODParameterRange sVddc;
+} ADLODParameters;
+static const ADLVersionsInfo version = {
+    "22.20.19.16-221003a-384125E-AMD-Software-Adrenalin-Edition",
+    "",
+    "http://support.amd.com/drivers/xml/driver_09_us.xml",
+};
+
+static const ADLVersionsInfoX2 version2 = {
+    "22.20.19.16-221003a-384125E-AMD-Software-Adrenalin-Edition",
+    "",
+    "22.10.1",
+    "http://support.amd.com/drivers/xml/driver_09_us.xml",
+};
+
+int WINAPI ADL_Main_Control_Create(ADL_MAIN_MALLOC_CALLBACK cb, int arg);
+int WINAPI ADL2_Main_Control_Create(ADL_MAIN_MALLOC_CALLBACK cb, int arg, ADL_CONTEXT_HANDLE *ptr)
+    FIXME("cb %p, arg %d, ptr %p stub!\n", cb, arg, ptr);
+    return ADL_Main_Control_Create(cb, arg);
+int WINAPI ADL_Main_Control_Create(ADL_MAIN_MALLOC_CALLBACK cb, int arg)
+    FIXME("cb %p, arg %d stub!\n", cb, arg);
+    adl_malloc = cb;
+    if (SUCCEEDED(CreateDXGIFactory(&IID_IDXGIFactory, (void**) &dxgi_factory)))
+        return ADL_OK;
+    else
+        return ADL_ERR;
+int WINAPI ADL_Main_Control_Destroy(void)
+    FIXME("stub!\n");
+    if (dxgi_factory != NULL)
+        IUnknown_Release(dxgi_factory);
+    return ADL_OK;
+int WINAPI ADL2_Main_Control_Destroy(void)
+{
+    FIXME("stub!\n");
+    return ADL_OK;
+}
+int WINAPI ADL_Adapter_NumberOfAdapters_Get(int *count);
+int WINAPI ADL2_Adapter_NumberOfAdapters_Get(ADL_CONTEXT_HANDLE *ptr, int *count)
+{
+    FIXME("ptr %p, count %p stub!\n", ptr, count);
+    return ADL_Adapter_NumberOfAdapters_Get(count);
+int WINAPI ADL2_Graphics_VersionsX2_Get(ADL_CONTEXT_HANDLE *ptr, ADLVersionsInfoX2 *ver)
+    FIXME("ptr %p, ver %p stub!\n", ptr, ver);
+    memcpy(ver, &version2, sizeof(version2));
+    return ADL_OK;
+}
+int WINAPI ADL_Graphics_Versions_Get(ADLVersionsInfo *ver)
+{
+    FIXME("ver %p stub!\n", ver);
+    memcpy(ver, &version, sizeof(version));
+    return ADL_OK;
+}
+int WINAPI ADL2_Adapter_Graphic_Core_Info_Get(ADL_CONTEXT_HANDLE *ptr, int iAdapterIndex, LPADLGraphicInfoCore pGraphicsInfo)
+{
+    FIXME("ptr %p, iAdapterIndex %u, pGraphicsInfo %p\n", ptr, iAdapterIndex, pGraphicsInfo);
+    return ADL_OK;
+}
+int WINAPI ADL2_Overdrive_Caps(ADL_CONTEXT_HANDLE *ptr, int iAdapterIndex, int *iSupported, int *iEnabled, int *iVersion)
+{
+    FIXME("ptr %p, iAdapterIndex %u\n");
+    *iSupported = 0;
+    *iEnabled = 0;
+    *iVersion = 0;
+    return ADL_OK;
+int WINAPI ADL_Adapter_NumberOfAdapters_Get(int *count)
+    IDXGIAdapter *adapter;
+    FIXME("count %p stub!\n", count);
+
+    *count = 0;
+    while (SUCCEEDED(IDXGIFactory_EnumAdapters(dxgi_factory, *count, &adapter)))
+        (*count)++;
+        IUnknown_Release(adapter);
+    TRACE("*count = %d\n", *count);
+    return ADL_OK;
+static int get_adapter_desc(int adapter_index, DXGI_ADAPTER_DESC *desc)
+    IDXGIAdapter *adapter;
+    if (FAILED(IDXGIFactory_EnumAdapters(dxgi_factory, adapter_index, &adapter)))
+        return ADL_ERR;
+    hr = IDXGIAdapter_GetDesc(adapter, desc);
+    IUnknown_Release(adapter);
+
+    return SUCCEEDED(hr) ? ADL_OK : ADL_ERR;
+/* yep, seriously */
+static int convert_vendor_id(int id)
+    char str[16];
+    snprintf(str, ARRAY_SIZE(str), "%x", id);
+    return atoi(str);
+}
+int WINAPI ADL_Adapter_AdapterInfo_Get(ADLAdapterInfo *adapters, int input_size);
+int WINAPI ADL2_Display_EdidData_Get(int adapter_index, int display_index, void* edid_data)
+{
+    FIXME("adapter_index %d, display_index %p, edid_data %p\n", 
+        adapter_index, display_index, edid_data);
+    return ADL_ERR_NOT_SUPPORTED;
+}
+
+int WINAPI ADL2_Adapter_AdapterInfoX2_Get(ADL_CONTEXT_HANDLE handle, ADLAdapterInfo **adapters)
+{
+    FIXME("stub!\n");
+    *adapters = (ADLAdapterInfo*)adl_malloc(sizeof(ADLAdapterInfo) * 1);
+    return ADL_Adapter_AdapterInfo_Get(*adapters, sizeof(ADLAdapterInfo) * 1);
+}
+
+int WINAPI ADL2_Adapter_AdapterInfoX4_Get(ADL_CONTEXT_HANDLE handle, int adapter_index, int *num_adapters, ADLAdapterInfoX2 **info)
+{
+    int status;
+    FIXME("adapter: %u, stub!\n", adapter_index);
+    if (adapter_index == -1)
+        adapter_index = 0;
+    if (num_adapters)
+        *num_adapters = 1;
+    *info = (ADLAdapterInfoX2*)adl_malloc(sizeof(ADLAdapterInfoX2) * 1);
+    memset(*info, 0, sizeof(ADLAdapterInfoX2));
+    status = ADL_Adapter_AdapterInfo_Get(*info, sizeof(ADLAdapterInfo));
+    if (status == ADL_OK)
+        info[0]->iInfoMask = 1; 
+        info[0]->iInfoValue = 1;
+    return status;
+int WINAPI ADL2_Adapter_AdapterInfo_Get(ADL_CONTEXT_HANDLE handle, ADLAdapterInfo *adapters, int bufferSize)
+    ADLAdapterInfo adapterInfo;
+    TRACE("stub!");
+    ADL_Adapter_AdapterInfo_Get(&adapterInfo, sizeof(ADLAdapterInfo));
+    if (bufferSize <= sizeof(ADLAdapterInfo))
+    {
+        memcpy(adapters, &adapterInfo, bufferSize);
+        return ADL_OK;
+    }
+
+    return ADL_ERR;
+int WINAPI ADL_Adapter_AdapterInfo_Get(ADLAdapterInfo *adapters, int input_size)
+    int count, i, j;
+    DXGI_ADAPTER_DESC adapter_desc;
+    FIXME("adapters %p, input_size %d, stub!\n", adapters, input_size);
+    ADL_Adapter_NumberOfAdapters_Get(&count);
+    if (!adapters) return ADL_ERR_INVALID_PARAM;
+    if (input_size != count * sizeof(ADLAdapterInfo)) return ADL_ERR_INVALID_PARAM;
+    memset(adapters, 0, input_size);
+    for (i = 0; i < count; i++)
+    {
+        adapters[i].iSize = sizeof(ADLAdapterInfo);
+        adapters[i].iAdapterIndex = i;
+        if (get_adapter_desc(i, &adapter_desc) != ADL_OK)
+            return ADL_ERR;
+        adapters[i].iVendorID = convert_vendor_id(adapter_desc.VendorId);
+        for (j = 0; j < 128; ++j)
+        {
+            adapters[i].strAdapterName[j] = (char)adapter_desc.Description[j];
+            if (adapters[i].strAdapterName[j] == 0)
+               break;
+        }
+    }
+
+    return ADL_OK;
+int WINAPI ADL_Display_DisplayInfo_Get(int adapter_index, int *num_displays, ADLDisplayInfo **info, int force_detect)
+    IDXGIAdapter *adapter;
+    IDXGIOutput *output;
+    int i;
+    FIXME("adapter %d, num_displays %p, info %p stub!\n", adapter_index, num_displays, info);
+    if (info == NULL || num_displays == NULL) return ADL_ERR_NULL_POINTER;
+    if (FAILED(IDXGIFactory_EnumAdapters(dxgi_factory, adapter_index, &adapter)))
+        return ADL_ERR_INVALID_PARAM;
+    *num_displays = 0;
+    while (SUCCEEDED(IDXGIAdapter_EnumOutputs(adapter, *num_displays, &output)))
+    {
+        (*num_displays)++;
+        IUnknown_Release(output);
+    }
+    IUnknown_Release(adapter);
+
+    if (*num_displays == 0)
+        return ADL_OK;
+
+    *info = adl_malloc(*num_displays * sizeof(**info));
+    memset(*info, 0, *num_displays * sizeof(**info));
+
+    for (i = 0; i < *num_displays; i++)
+    {
+        (*info)[i].displayID.iDisplayLogicalIndex = i;
+        (*info)[i].iDisplayInfoValue = ADL_DISPLAY_DISPLAYINFO_DISPLAYCONNECTED | ADL_DISPLAY_DISPLAYINFO_DISPLAYMAPPED;
+        (*info)[i].iDisplayInfoMask = (*info)[i].iDisplayInfoValue;
+    }
+
+    return ADL_OK;
+int WINAPI ADL2_Display_DisplayInfo_Get(ADL_CONTEXT_HANDLE context, int adapter_index, int *num_displays, ADLDisplayInfo **info, int force_detect)
+    FIXME("adapter: %d, stub!\n", adapter_index);
+    return ADL_Display_DisplayInfo_Get(adapter_index, num_displays, info, force_detect);    
+int WINAPI ADL_Adapter_Crossfire_Caps(int adapter_index, int *preffered, int *num_comb, ADLCrossfireComb** comb)
+    FIXME("adapter %d, preffered %p, num_comb %p, comb %p stub!\n", adapter_index, preffered, num_comb, comb);
+    return ADL_ERR;
+int WINAPI ADL_Adapter_Crossfire_Get(int adapter_index, ADLCrossfireComb *comb, ADLCrossfireInfo *info)
+    FIXME("adapter %d, comb %p, info %p, stub!\n", adapter_index, comb, info);
+    return ADL_ERR;
+int WINAPI ADL_Adapter_ASICFamilyType_Get(int adapter_index, int *asic_type, int *valids)
+    DXGI_ADAPTER_DESC adapter_desc;
+    FIXME("adapter %d, asic_type %p, valids %p, stub!\n", adapter_index, asic_type, valids);
+    if (asic_type == NULL || valids == NULL)
+        return  ADL_ERR_NULL_POINTER;
+    if (get_adapter_desc(adapter_index, &adapter_desc) != ADL_OK)
+        return ADL_ERR_INVALID_ADL_IDX;
+    if (adapter_desc.VendorId != VENDOR_AMD)
+        return ADL_ERR_NOT_SUPPORTED;
+    *asic_type = ADL_ASIC_DISCRETE;
+    *valids = ADL_ASIC_MASK;
+    return ADL_OK;
+int WINAPI ADL2_Adapter_ASICFamilyType_Get(ADL_CONTEXT_HANDLE handle, int adapter_index, int *asic_types, int *valids)
+    FIXME("adapter_index: %u, stub!\n", adapter_index);
+    return ADL_Adapter_ASICFamilyType_Get(adapter_index, asic_types, valids);
+}
+static int get_max_clock(const char *clock, int default_value)
+    char path[MAX_PATH], line[256];
+    FILE *file;
+    int drm_card, value = 0;
+    for (drm_card = 0; drm_card < MAX_GPUS; drm_card++)
+    {
+        sprintf(path, "/sys/class/drm/card%d/device/pp_dpm_%s", drm_card, clock);
+        file = fopen(path, "r");
+        if (file == NULL)
+            continue;
+        while (fgets(line, sizeof(line), file) != NULL)
+        {
+            char *number;
+            number = strchr(line, ' ');
+            if (number == NULL)
+            {
+                WARN("pp_dpm_%s file has unexpected format\n", clock);
+                break;
+            }
+            number++;
+            value = max(strtol(number, NULL, 0), value);
+        }
+    if (value != 0)
+        return value;
+    return default_value;
+/* documented in the "Linux Specific APIs" section, present and used on Windows */
+/* the name and documentation suggests that this returns current freqs, but it's actually max */
+int WINAPI ADL_Adapter_ObservedClockInfo_Get(int adapter_index, int *core_clock, int *memory_clock)
+    DXGI_ADAPTER_DESC adapter_desc;
+    FIXME("adapter %d, core_clock %p, memory_clock %p, stub!\n", adapter_index, core_clock, memory_clock);
+    if (core_clock == NULL || memory_clock == NULL) return ADL_ERR;
+    if (get_adapter_desc(adapter_index, &adapter_desc) != ADL_OK) return ADL_ERR;
+    if (adapter_desc.VendorId != VENDOR_AMD) return ADL_ERR_INVALID_ADL_IDX;
+    /* default values based on RX580 */
+    *core_clock = get_max_clock("sclk", 1350);
+    *memory_clock = get_max_clock("mclk", 2000);
+
+    TRACE("*core_clock: %i, *memory_clock %i\n", *core_clock, *memory_clock);
+
+    return ADL_OK;
+}
+
+int WINAPI ADL_Adapter_ObservedGameClockInfo_Get(ADL_CONTEXT_HANDLE context, int adapter_index, int* base_clock, int* game_clock, int* boost_clock, int* memory_clock)
+{
+    int retStatus;
+    FIXME("adapter: %d, stub!\n", adapter_index);
+    retStatus = ADL_Adapter_ObservedClockInfo_Get(adapter_index, base_clock, memory_clock);
+    if (retStatus == ADL_OK)
+    {
+        *game_clock = *base_clock;
+        *boost_clock = *base_clock;
+
+        TRACE("*base_clock: %i, *game_clock: %i, *boost_clock: %i, *memory_clock: %i\n", 
+                *base_clock, *game_clock, *boost_clock, *memory_clock);
+    }
+    return retStatus;
+}
+/* documented in the "Linux Specific APIs" section, present and used on Windows */
+int WINAPI ADL_Adapter_MemoryInfo_Get(int adapter_index, ADLMemoryInfo *mem_info)
+    DXGI_ADAPTER_DESC adapter_desc;
+    FIXME("adapter %d, mem_info %p stub!\n", adapter_index, mem_info);
+    if (mem_info == NULL) return ADL_ERR_NULL_POINTER;
+    if (get_adapter_desc(adapter_index, &adapter_desc) != ADL_OK) return ADL_ERR_INVALID_ADL_IDX;
+    if (adapter_desc.VendorId != VENDOR_AMD) return ADL_ERR;
+
+    mem_info->iMemorySize = adapter_desc.DedicatedVideoMemory;
+    mem_info->iMemoryBandwidth = 256000; /* not exposed on Linux, probably needs a lookup table */
+
+    TRACE("iMemoryBandwidth %s, iMemorySize %s\n",
+            wine_dbgstr_longlong(mem_info->iMemoryBandwidth),
+            wine_dbgstr_longlong(mem_info->iMemorySize));
+    return ADL_OK;
+int WINAPI ADL2_Adapter_MemoryInfo_Get(ADL_CONTEXT_HANDLE context, int adapter_index, ADLMemoryInfo *mem_info)
+    FIXME("adapter %d, stub!\n", adapter_index);
+    return ADL_Adapter_MemoryInfo_Get(adapter_index, mem_info);
+}
+int WINAPI ADL2_Adapter_MemoryInfo2_Get(ADL_CONTEXT_HANDLE context, int adapter_index, ADLMemoryInfo2 *mem_info)
+{
+    ADLMemoryInfo meminfo1;
+    int status;
+    FIXME("adapter %d, stub!\n", adapter_index);
+    
+    status = ADL2_Adapter_MemoryInfo_Get(context, adapter_index, &meminfo1);
+    if (status == ADL_OK)
+        mem_info->iHyperMemorySize = 0;
+        mem_info->iInvisibleMemorySize = 0;
+        mem_info->iMemoryBandwidth = meminfo1.iMemoryBandwidth;
+        mem_info->iMemorySize = meminfo1.iMemorySize;
+        mem_info->iVisibleMemorySize = mem_info->iMemorySize;
+        memcpy(mem_info->strMemoryType, meminfo1.strMemoryType, ADL_MAX_PATH);
+    return status;
+int WINAPI ADL_Adapter_Primary_Get(int* adapter_index)
+    FIXME("stub!\n");
+    *adapter_index = 0;
+    return ADL_OK;
+int WINAPI ADL_Graphics_Platform_Get(int *platform)
+    DXGI_ADAPTER_DESC adapter_desc;
+    int count, i;
+    FIXME("platform %p, stub!\n", platform);
+    *platform = GRAPHICS_PLATFORM_UNKNOWN;
+
+    ADL_Adapter_NumberOfAdapters_Get(&count);
+
+    for (i = 0; i < count; i ++)
+        if (get_adapter_desc(i, &adapter_desc) != ADL_OK)
+            continue;
+
+        if (adapter_desc.VendorId == VENDOR_AMD)
+            *platform = GRAPHICS_PLATFORM_DESKTOP;
+    /* NOTE: The real value can be obtained by doing:
+     * 1. ioctl(DRM_AMDGPU_INFO) with AMDGPU_INFO_DEV_INFO - dev_info.ids_flags & AMDGPU_IDS_FLAGS_FUSION
+     * 2. VkPhysicalDeviceType() if we ever want to use Vulkan directly
+     */
+    return ADL_OK;
+
+int WINAPI ADL_Display_DisplayMapConfig_Get(int adapter_index, int *display_map_count, ADLDisplayMap **display_maps,
+        int *display_target_count, ADLDisplayTarget **display_targets, int options)
+    FIXME("adapter_index %d, display_map_count %p, display_maps %p, "
+            "display_target_count %p, display_targets %p, options %d stub.\n",
+            adapter_index, display_map_count, display_maps, display_target_count,
+            display_targets, options);
+
+    return ADL_ERR_NOT_SUPPORTED;
+int WINAPI ADL2_Display_DisplayMapConfig_Get(ADL_CONTEXT_HANDLE context, int adapter_index, int *display_map_count, ADLDisplayMap **display_maps,
+        int *display_target_count, ADLDisplayTarget **display_targets, int options)
+    FIXME("adapter_index %d, stub!\n", adapter_index);
+    return ADL_Display_DisplayMapConfig_Get(adapter_index, display_map_count, display_maps, display_target_count, display_targets, options);
+int WINAPI ADL_Display_EdidData_Get(int adapter_index, int display_index, void* edid_data)
+    FIXME("adapter_index %d, display_index %p, edid_data %p\n", 
+        adapter_index, display_index, edid_data);
+    return ADL_ERR_NOT_SUPPORTED;
+int WINAPI ADL2_Display_Modes_Get(ADL_CONTEXT_HANDLE context, int adapter_index, int display_index, int *num_modes, ADLMode *modes)
+    FIXME("adapter: %d, display: %d, stub!\n", adapter_index, display_index);
+    return ADL_ERR_NOT_SUPPORTED;
+int WINAPI ADL2_Display_DDCInfo2_Get(ADL_CONTEXT_HANDLE context, int adapter_index, int display_index, ADLDDCInfo2 *info)
+    FIXME("adapter: %d, display: %d, stub!\n", adapter_index, display_index);
+    return ADL_ERR_NOT_SUPPORTED;
+int WINAPI ADL2_Display_FreeSync_Cap(ADL_CONTEXT_HANDLE context, int adapter_index, int display_index, ADLFreeSyncCap *cap)
+    FIXME("adapter: %d, display: %d, stub!\n", adapter_index, display_index);
+    return ADL_ERR_NOT_SUPPORTED;
+}
+int WINAPI ADL_Overdrive5_ODParameters_Get(int iAdapterIndex, ADLODParameters *lpOdParameters)
+    return ADL_ERR_NOT_SUPPORTED;
+}
+int WINAPI ADL2_Overdrive5_ODParameters_Get(ADL_CONTEXT_HANDLE context, int iAdapterIndex, ADLODParameters *lpOdParameters)
+    return ADL_ERR_NOT_SUPPORTED;
diff --git a/wine/dlls/crypt32/base64.c b/wine/dlls/crypt32/base64.c
index 11fb137ed..b61ed7ff8 100644
--- a/wine/dlls/crypt32/base64.c
+++ b/wine/dlls/crypt32/base64.c
@@ -241,6 +241,63 @@ static BOOL BinaryToBase64A(const BYTE *pbBinary,
     return ret;
}

+static BOOL BinaryToHexRawA(const BYTE *bin, DWORD nbin, DWORD flags, char *str, DWORD *nstr)
+    static const char hex[] = "0123456789abcdef";
+    DWORD needed;
+    if (flags & CRYPT_STRING_NOCRLF)
+        needed = 0;
+    else if (flags & CRYPT_STRING_NOCR)
+        needed = 1;
+    else
+        needed = 2;
+    needed += nbin * 2 + 1;
+
+    if (!str)
+        *nstr = needed;
+        return TRUE;
+    if (needed > *nstr && *nstr < 3)
+        SetLastError(ERROR_MORE_DATA);
+        return FALSE;
+    nbin = min(nbin, (*nstr - 1) / 2);
+    while (nbin--)
+    {
+        *str++ = hex[(*bin >> 4) & 0xf];
+        *str++ = hex[*bin & 0xf];
+        bin++;
+    }
+
+    if (needed > *nstr)
+    {
+        *str = 0;
+        SetLastError(ERROR_MORE_DATA);
+        return FALSE;
+    }
+
+    if (flags & CRYPT_STRING_NOCR)
+    {
+        *str++ = '\n';
+    }
+    else if (!(flags & CRYPT_STRING_NOCRLF))
+    {
+        *str++ = '\r';
+        *str++ = '\n';
+    }
+
+    *str = 0;
+    *nstr = needed - 1;
+    return TRUE;
BOOL WINAPI CryptBinaryToStringA(const BYTE *pbBinary,
DWORD cbBinary, DWORD dwFlags, LPSTR pszString, DWORD *pcchString)
{
@@ -271,6 +328,9 @@ BOOL WINAPI CryptBinaryToStringA(const BYTE *pbBinary,
     case CRYPT_STRING_BASE64X509CRLHEADER:
          encoder = BinaryToBase64A;
          break;
+    case CRYPT_STRING_HEXRAW:
+        encoder = BinaryToHexRawA;
+        break;
     case CRYPT_STRING_HEX:
     case CRYPT_STRING_HEXASCII:
     case CRYPT_STRING_HEXADDR:
@@ -883,6 +943,120 @@ static LONG DecodeAnyA(LPCSTR pszString, DWORD cchString,
     return ret;
}

+static BOOL is_hex_string_special_char(WCHAR c)
+    switch (c)
+    {
+        case '-':
+        case ',':
+        case ' ':
+        case '\t':
+        case '\r':
+        case '\n':
+            return TRUE;
+
+        default:
+            return FALSE;
+    }
+static WCHAR wchar_from_str(BOOL wide, const void **str, DWORD *len)
+    WCHAR c;
+
+    if (!*len)
+        return 0;
+
+    --*len;
+    if (wide)
+        c = *(*(const WCHAR **)str)++;
+    else
+        c = *(*(const char **)str)++;
+
+    return c ? c : 0xffff;
+static BYTE digit_from_char(WCHAR c)
+    if (c >= '0' && c <= '9')
+        return c - '0';
+    c = towlower(c);
+    if (c >= 'a' && c <= 'f')
+        return c - 'a' + 0xa;
+    return 0xff;
+static LONG string_to_hex(const void* str, BOOL wide, DWORD len, BYTE *hex, DWORD *hex_len,
+        DWORD *skipped, DWORD *ret_flags)
+    unsigned int byte_idx = 0;
+    BYTE d1, d2;
+    WCHAR c;
+
+    if (!str || !hex_len)
+        return ERROR_INVALID_PARAMETER;
+
+    if (!len)
+        len = wide ? wcslen(str) : strlen(str);
+
+    if (wide && !len)
+        return ERROR_INVALID_PARAMETER;
+
+    if (skipped)
+        *skipped = 0;
+    if (ret_flags)
+        *ret_flags = 0;
+
+    while ((c = wchar_from_str(wide, &str, &len)) && is_hex_string_special_char(c))
+        ;
+
+    while ((d1 = digit_from_char(c)) != 0xff)
+    {
+        if ((d2 = digit_from_char(wchar_from_str(wide, &str, &len))) == 0xff)
+        {
+            if (!hex)
+                *hex_len = 0;
+            return ERROR_INVALID_DATA;
+        }
+
+        if (hex && byte_idx < *hex_len)
+            hex[byte_idx] = (d1 << 4) | d2;
+
+        ++byte_idx;
+
+        do
+        {
+            c = wchar_from_str(wide, &str, &len);
+        } while (c == '-' || c == ',');
+    }
+
+    while (c)
+    {
+        if (!is_hex_string_special_char(c))
+        {
+            if (!hex)
+                *hex_len = 0;
+            return ERROR_INVALID_DATA;
+        }
+        c = wchar_from_str(wide, &str, &len);
+    }
+
+    if (hex && byte_idx > *hex_len)
+        return ERROR_MORE_DATA;
+
+    if (ret_flags)
+        *ret_flags = CRYPT_STRING_HEX;
+
+    *hex_len = byte_idx;
+
+    return ERROR_SUCCESS;
+static LONG string_to_hexA(const char *str, DWORD len, BYTE *hex, DWORD *hex_len, DWORD *skipped, DWORD *ret_flags)
+    return string_to_hex(str, FALSE, len, hex, hex_len, skipped, ret_flags);
BOOL WINAPI CryptStringToBinaryA(LPCSTR pszString,
DWORD cchString, DWORD dwFlags, BYTE *pbBinary, DWORD *pcbBinary,
DWORD *pdwSkip, DWORD *pdwFlags)
@@ -928,6 +1102,8 @@ BOOL WINAPI CryptStringToBinaryA(LPCSTR pszString,
          decoder = DecodeAnyA;
          break;
     case CRYPT_STRING_HEX:
+        decoder = string_to_hexA;
+        break;
     case CRYPT_STRING_HEXASCII:
     case CRYPT_STRING_HEXADDR:
     case CRYPT_STRING_HEXASCIIADDR:
@@ -1094,6 +1270,11 @@ static LONG DecodeAnyW(LPCWSTR pszString, DWORD cchString,
     return ret;
}

+static LONG string_to_hexW(const WCHAR *str, DWORD len, BYTE *hex, DWORD *hex_len, DWORD *skipped, DWORD *ret_flags)
+    return string_to_hex(str, TRUE, len, hex, hex_len, skipped, ret_flags);
+}
BOOL WINAPI CryptStringToBinaryW(LPCWSTR pszString,
DWORD cchString, DWORD dwFlags, BYTE *pbBinary, DWORD *pcbBinary,
DWORD *pdwSkip, DWORD *pdwFlags)
@@ -1139,6 +1320,8 @@ BOOL WINAPI CryptStringToBinaryW(LPCWSTR pszString,
          decoder = DecodeAnyW;
          break;
     case CRYPT_STRING_HEX:
+        decoder = string_to_hexW;
+        break;
     case CRYPT_STRING_HEXASCII:
     case CRYPT_STRING_HEXADDR:
     case CRYPT_STRING_HEXASCIIADDR:
diff --git a/wine/dlls/crypt32/cert.c b/wine/dlls/crypt32/cert.c
index ad39b7d18..b57cc6852 100644
--- a/wine/dlls/crypt32/cert.c
+++ b/wine/dlls/crypt32/cert.c
@@ -1006,6 +1006,7 @@ BOOL WINAPI CryptAcquireCertificatePrivateKey(PCCERT_CONTEXT pCert,
     CryptMemFree(info);
     if (cert_in_store)
          CertFreeCertificateContext(cert_in_store);
+    if (ret) SetLastError(0);
     return ret;
}

diff --git a/wine/dlls/crypt32/chain.c b/wine/dlls/crypt32/chain.c
index cf244f2ac..4a60e9a60 100644
--- a/wine/dlls/crypt32/chain.c
+++ b/wine/dlls/crypt32/chain.c
@@ -3696,6 +3696,44 @@ static BYTE msPubKey4[] = {
0xa6,0xc6,0x48,0x4c,0xc3,0x37,0x51,0x23,0xd3,0x27,0xd7,0xb8,0x4e,0x70,0x96,
0xf0,0xa1,0x44,0x76,0xaf,0x78,0xcf,0x9a,0xe1,0x66,0x13,0x02,0x03,0x01,0x00,
0x01 };
+/* from Microsoft Root Certificate Authority 2011 */
+static BYTE msPubKey5[] = {
+0x30,0x82,0x02,0x0a,0x02,0x82,0x02,0x01,0x00,0xb2,0x80,0x41,0xaa,0x35,0x38,
+0x4d,0x13,0x72,0x32,0x68,0x22,0x4d,0xb8,0xb2,0xf1,0xff,0xd5,0x52,0xbc,0x6c,
+0xc7,0xf5,0xd2,0x4a,0x8c,0x36,0xee,0xd1,0xc2,0x5c,0x7e,0x8c,0x8a,0xae,0xaf,
+0x13,0x28,0x6f,0xc0,0x73,0xe3,0x3a,0xce,0xd0,0x25,0xa8,0x5a,0x3a,0x6d,0xef,
+0xa8,0xb8,0x59,0xab,0x13,0x23,0x68,0xcd,0x0c,0x29,0x87,0xd1,0x6f,0x80,0x5c,
+0x8f,0x44,0x7f,0x5d,0x90,0x01,0x52,0x58,0xac,0x51,0xc5,0x5f,0x2a,0x87,0xdc,
+0xdc,0xd8,0x0a,0x1d,0xc1,0x03,0xb9,0x7b,0xb0,0x56,0xe8,0xa3,0xde,0x64,0x61,
+0xc2,0x9e,0xf8,0xf3,0x7c,0xb9,0xec,0x0d,0xb5,0x54,0xfe,0x4c,0xb6,0x65,0x4f,
+0x88,0xf0,0x9c,0x48,0x99,0x0c,0x42,0x0b,0x09,0x7c,0x31,0x59,0x17,0x79,0x06,
+0x78,0x28,0x8d,0x89,0x3a,0x4c,0x03,0x25,0xbe,0x71,0x6a,0x5c,0x0b,0xe7,0x84,
+0x60,0xa4,0x99,0x22,0xe3,0xd2,0xaf,0x84,0xa4,0xa7,0xfb,0xd1,0x98,0xed,0x0c,
+0xa9,0xde,0x94,0x89,0xe1,0x0e,0xa0,0xdc,0xc0,0xce,0x99,0x3d,0xea,0x08,0x52,
+0xbb,0x56,0x79,0xe4,0x1f,0x84,0xba,0x1e,0xb8,0xb4,0xc4,0x49,0x5c,0x4f,0x31,
+0x4b,0x87,0xdd,0xdd,0x05,0x67,0x26,0x99,0x80,0xe0,0x71,0x11,0xa3,0xb8,0xa5,
+0x41,0xe2,0xa4,0x53,0xb9,0xf7,0x32,0x29,0x83,0x0c,0x13,0xbf,0x36,0x5e,0x04,
+0xb3,0x4b,0x43,0x47,0x2f,0x6b,0xe2,0x91,0x1e,0xd3,0x98,0x4f,0xdd,0x42,0x07,
+0xc8,0xe8,0x1d,0x12,0xfc,0x99,0xa9,0x6b,0x3e,0x92,0x7e,0xc8,0xd6,0x69,0x3a,
+0xfc,0x64,0xbd,0xb6,0x09,0x9d,0xca,0xfd,0x0c,0x0b,0xa2,0x9b,0x77,0x60,0x4b,
+0x03,0x94,0xa4,0x30,0x69,0x12,0xd6,0x42,0x2d,0xc1,0x41,0x4c,0xca,0xdc,0xaa,
+0xfd,0x8f,0x5b,0x83,0x46,0x9a,0xd9,0xfc,0xb1,0xd1,0xe3,0xb3,0xc9,0x7f,0x48,
+0x7a,0xcd,0x24,0xf0,0x41,0x8f,0x5c,0x74,0xd0,0xac,0xb0,0x10,0x20,0x06,0x49,
+0xb7,0xc7,0x2d,0x21,0xc8,0x57,0xe3,0xd0,0x86,0xf3,0x03,0x68,0xfb,0xd0,0xce,
+0x71,0xc1,0x89,0x99,0x4a,0x64,0x01,0x6c,0xfd,0xec,0x30,0x91,0xcf,0x41,0x3c,
+0x92,0xc7,0xe5,0xba,0x86,0x1d,0x61,0x84,0xc7,0x5f,0x83,0x39,0x62,0xae,0xb4,
+0x92,0x2f,0x47,0xf3,0x0b,0xf8,0x55,0xeb,0xa0,0x1f,0x59,0xd0,0xbb,0x74,0x9b,
+0x1e,0xd0,0x76,0xe6,0xf2,0xe9,0x06,0xd7,0x10,0xe8,0xfa,0x64,0xde,0x69,0xc6,
+0x35,0x96,0x88,0x02,0xf0,0x46,0xb8,0x3f,0x27,0x99,0x6f,0xcb,0x71,0x89,0x29,
+0x35,0xf7,0x48,0x16,0x02,0x35,0x8f,0xd5,0x79,0x7c,0x4d,0x02,0xcf,0x5f,0xeb,
+0x8a,0x83,0x4f,0x45,0x71,0x88,0xf9,0xa9,0x0d,0x4e,0x72,0xe9,0xc2,0x9c,0x07,
+0xcf,0x49,0x1b,0x4e,0x04,0x0e,0x63,0x51,0x8c,0x5e,0xd8,0x00,0xc1,0x55,0x2c,
+0xb6,0xc6,0xe0,0xc2,0x65,0x4e,0xc9,0x34,0x39,0xf5,0x9c,0xb3,0xc4,0x7e,0xe8,
+0x61,0x6e,0x13,0x5f,0x15,0xc4,0x5f,0xd9,0x7e,0xed,0x1d,0xce,0xee,0x44,0xec,
+0xcb,0x2e,0x86,0xb1,0xec,0x38,0xf6,0x70,0xed,0xab,0x5c,0x13,0xc1,0xd9,0x0f,
+0x0d,0xc7,0x80,0xb2,0x55,0xed,0x34,0xf7,0xac,0x9b,0xe4,0xc3,0xda,0xe7,0x47,
+0x3c,0xa6,0xb5,0x8f,0x31,0xdf,0xc5,0x4b,0xaf,0xeb,0xf1,0x02,0x03,0x01,0x00,
+0x01 };

static BOOL WINAPI verify_ms_root_policy(LPCSTR szPolicyOID,
PCCERT_CHAIN_CONTEXT pChainContext, PCERT_CHAIN_POLICY_PARA pPolicyPara,
@@ -3705,21 +3743,38 @@ static BOOL WINAPI verify_ms_root_policy(LPCSTR szPolicyOID,

     CERT_PUBLIC_KEY_INFO msPubKey = { { 0 } };
     DWORD i;
-    CRYPT_DATA_BLOB keyBlobs[] = {
+    static const CRYPT_DATA_BLOB keyBlobs[] = {
          { sizeof(msPubKey1), msPubKey1 },
          { sizeof(msPubKey2), msPubKey2 },
          { sizeof(msPubKey3), msPubKey3 },
          { sizeof(msPubKey4), msPubKey4 },
     };
+    static const CRYPT_DATA_BLOB keyBlobs_approot[] = {
+        { sizeof(msPubKey5), msPubKey5 },
+    };
     PCERT_SIMPLE_CHAIN rootChain =
          pChainContext->rgpChain[pChainContext->cChain - 1];
     PCCERT_CONTEXT root =
          rootChain->rgpElement[rootChain->cElement - 1]->pCertContext;

-    for (i = 0; !isMSRoot && i < ARRAY_SIZE(keyBlobs); i++)
+    const CRYPT_DATA_BLOB *keys;
+    unsigned int key_count;
+    if (pPolicyPara && pPolicyPara->dwFlags & MICROSOFT_ROOT_CERT_CHAIN_POLICY_CHECK_APPLICATION_ROOT_FLAG)
+    {
+        keys = keyBlobs_approot;
+        key_count = ARRAY_SIZE(keyBlobs_approot);
+    }
+    else
+    {
+        keys = keyBlobs;
+        key_count = ARRAY_SIZE(keyBlobs);
+    }
+    for (i = 0; !isMSRoot && i < key_count; i++)
     {
-        msPubKey.PublicKey.cbData = keyBlobs[i].cbData;
-        msPubKey.PublicKey.pbData = keyBlobs[i].pbData;
+        msPubKey.PublicKey.cbData = keys[i].cbData;
+        msPubKey.PublicKey.pbData = keys[i].pbData;
          if (CertComparePublicKeyInfo(X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
               &root->pCertInfo->SubjectPublicKeyInfo, &msPubKey)) isMSRoot = TRUE;
     }
diff --git a/wine/dlls/crypt32/decode.c b/wine/dlls/crypt32/decode.c
index 762d1b546..19643194b 100644
--- a/wine/dlls/crypt32/decode.c
+++ b/wine/dlls/crypt32/decode.c
@@ -3874,7 +3874,7 @@ static BOOL WINAPI CRYPT_AsnDecodeCertPolicyConstraints(

struct DECODED_RSA_PUB_KEY
{
-    DWORD              pubexp;
+    CRYPT_INTEGER_BLOB pubexp;
     CRYPT_INTEGER_BLOB modulus;
};

@@ -3893,12 +3893,23 @@ static BOOL CRYPT_raw_decode_rsa_pub_key(struct DECODED_RSA_PUB_KEY **decodedKey
          FALSE, TRUE, offsetof(struct DECODED_RSA_PUB_KEY, modulus.pbData),
          0 },
     { ASN_INTEGER, offsetof(struct DECODED_RSA_PUB_KEY, pubexp),
-       CRYPT_AsnDecodeIntInternal, sizeof(DWORD), FALSE, FALSE, 0, 0 },
+       CRYPT_AsnDecodeUnsignedIntegerInternal, sizeof(CRYPT_INTEGER_BLOB),
+       FALSE, TRUE, offsetof(struct DECODED_RSA_PUB_KEY, pubexp.pbData),
+       0 },
     };

     ret = CRYPT_AsnDecodeSequence(items, ARRAY_SIZE(items),
     pbEncoded, cbEncoded, CRYPT_DECODE_ALLOC_FLAG, NULL, decodedKey,
     size, NULL, NULL);
+    if (ret && (*decodedKey)->pubexp.cbData > sizeof(DWORD))
+        WARN("Unexpected exponent length %lu.\n", (*decodedKey)->pubexp.cbData);
+        LocalFree(*decodedKey);
+        SetLastError(CRYPT_E_ASN1_LARGE);
+        ret = FALSE;
     return ret;
}

@@ -3920,7 +3931,7 @@ static BOOL WINAPI CRYPT_AsnDecodeRsaPubKey_Bcrypt(DWORD dwCertEncodingType,
          if (ret)
          {
               /* Header, exponent, and modulus */
-            DWORD bytesNeeded = sizeof(BCRYPT_RSAKEY_BLOB) + sizeof(DWORD) +
+            DWORD bytesNeeded = sizeof(BCRYPT_RSAKEY_BLOB) + decodedKey->pubexp.cbData +
               decodedKey->modulus.cbData;

               if (!pvStructInfo)
@@ -3939,7 +3950,7 @@ static BOOL WINAPI CRYPT_AsnDecodeRsaPubKey_Bcrypt(DWORD dwCertEncodingType,
               hdr = pvStructInfo;
               hdr->Magic = BCRYPT_RSAPUBLIC_MAGIC;
               hdr->BitLength = decodedKey->modulus.cbData * 8;
-                hdr->cbPublicExp = sizeof(DWORD);
+                hdr->cbPublicExp = decodedKey->pubexp.cbData;
               hdr->cbModulus = decodedKey->modulus.cbData;
               hdr->cbPrime1 = 0;
               hdr->cbPrime2 = 0;
@@ -3947,9 +3958,9 @@ static BOOL WINAPI CRYPT_AsnDecodeRsaPubKey_Bcrypt(DWORD dwCertEncodingType,
                    * in big-endian format, so we need to convert from little-endian
                    */
               CRYPT_CopyReversed((BYTE *)pvStructInfo + sizeof(BCRYPT_RSAKEY_BLOB),
-                 (BYTE *)&decodedKey->pubexp, sizeof(DWORD));
+                 decodedKey->pubexp.pbData, hdr->cbPublicExp);
               CRYPT_CopyReversed((BYTE *)pvStructInfo + sizeof(BCRYPT_RSAKEY_BLOB) +
-                 sizeof(DWORD), decodedKey->modulus.pbData,
+                 hdr->cbPublicExp, decodedKey->modulus.pbData,
                    decodedKey->modulus.cbData);
               }
               LocalFree(decodedKey);
@@ -3984,13 +3995,13 @@ static BOOL WINAPI CRYPT_AsnDecodeRsaPubKey(DWORD dwCertEncodingType,
               if (!pvStructInfo)
               {
               *pcbStructInfo = bytesNeeded;
-                ret = TRUE;
               }
               else if ((ret = CRYPT_DecodeEnsureSpace(dwFlags, pDecodePara,
               pvStructInfo, pcbStructInfo, bytesNeeded)))
               {
               BLOBHEADER *hdr;
               RSAPUBKEY *rsaPubKey;
+                unsigned int i;

               if (dwFlags & CRYPT_DECODE_ALLOC_FLAG)
                    pvStructInfo = *(BYTE **)pvStructInfo;
@@ -4002,7 +4013,11 @@ static BOOL WINAPI CRYPT_AsnDecodeRsaPubKey(DWORD dwCertEncodingType,
               rsaPubKey = (RSAPUBKEY *)((BYTE *)pvStructInfo +
                    sizeof(BLOBHEADER));
               rsaPubKey->magic = RSA1_MAGIC;
-                rsaPubKey->pubexp = decodedKey->pubexp;
+                rsaPubKey->pubexp = 0;
+                assert(decodedKey->pubexp.cbData <= sizeof(rsaPubKey->pubexp));
+                for (i = 0; i < decodedKey->pubexp.cbData; ++i)
+                    rsaPubKey->pubexp |= decodedKey->pubexp.pbData[i] << (i * 8);
               rsaPubKey->bitlen = decodedKey->modulus.cbData * 8;
               memcpy((BYTE *)pvStructInfo + sizeof(BLOBHEADER) +
                    sizeof(RSAPUBKEY), decodedKey->modulus.pbData,
@@ -6351,6 +6366,112 @@ static BOOL CRYPT_AsnDecodeOCSPNextUpdate(const BYTE *pbEncoded,
     return ret;
}

+static BOOL CRYPT_AsnDecodeCertStatus(const BYTE *pbEncoded,
+ DWORD cbEncoded, DWORD dwFlags, void *pvStructInfo, DWORD *pcbStructInfo,
+ DWORD *pcbDecoded)
+    BOOL ret = TRUE;
+    BYTE tag = pbEncoded[0] & ~3, status = pbEncoded[0] & 3;
+    DWORD bytesNeeded = FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, ThisUpdate) -
+                        FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, dwCertStatus);
+    if (!cbEncoded)
+    {
+        SetLastError(CRYPT_E_ASN1_EOD);
+        return FALSE;
+    }
+    switch (status)
+    {
+    case 0:
+        if (tag != ASN_CONTEXT)
+        {
+            WARN("Unexpected tag %02x\n", tag);
+            SetLastError(CRYPT_E_ASN1_BADTAG);
+            return FALSE;
+        }
+        if (cbEncoded < 2 || pbEncoded[1])
+        {
+            SetLastError(CRYPT_E_ASN1_CORRUPT);
+            return FALSE;
+        }
+        if (!pvStructInfo)
+            *pcbStructInfo = bytesNeeded;
+        else if (*pcbStructInfo < bytesNeeded)
+        {
+            *pcbStructInfo = bytesNeeded;
+            SetLastError(ERROR_MORE_DATA);
+            return FALSE;
+        }
+        if (pvStructInfo)
+        {
+            *(DWORD *)pvStructInfo = 0;
+            *(OCSP_BASIC_REVOKED_INFO **)((char *)pvStructInfo
+                + FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, u.pRevokedInfo)
+                - FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, dwCertStatus)) = NULL;
+        }
+        *pcbStructInfo = bytesNeeded;
+        *pcbDecoded = 2;
+        break;
+    case 1:
+    {
+        DWORD dataLen;
+        if (tag != (ASN_CONTEXT | ASN_CONSTRUCTOR))
+        {
+            WARN("Unexpected tag %02x\n", tag);
+            SetLastError(CRYPT_E_ASN1_BADTAG);
+            return FALSE;
+        }
+        if ((ret = CRYPT_GetLen(pbEncoded, cbEncoded, &dataLen)))
+        {
+            BYTE lenBytes = GET_LEN_BYTES(pbEncoded[1]);
+            DWORD bytesDecoded, size;
+            FILETIME date;
+            if (dataLen)
+            {
+                size = sizeof(date);
+                ret = CRYPT_AsnDecodeGeneralizedTime(pbEncoded + 1 + lenBytes, cbEncoded - 1 - lenBytes,
+                 dwFlags, &date, &size, &bytesDecoded);
+                if (ret)
+                {
+                    OCSP_BASIC_REVOKED_INFO *info;
+                    bytesNeeded += sizeof(*info);
+                    if (!pvStructInfo)
+                        *pcbStructInfo = bytesNeeded;
+                    else if (*pcbStructInfo < bytesNeeded)
+                    {
+                        *pcbStructInfo = bytesNeeded;
+                        SetLastError(ERROR_MORE_DATA);
+                        return FALSE;
+                    }
+                    if (pvStructInfo)
+                    {
+                        *(DWORD *)pvStructInfo = 1;
+                        info = *(OCSP_BASIC_REVOKED_INFO **)((char *)pvStructInfo
+                            + FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, u.pRevokedInfo)
+                            - FIELD_OFFSET(OCSP_BASIC_RESPONSE_ENTRY, dwCertStatus));
+                        info->RevocationDate = date;
+                    }
+                    *pcbStructInfo = bytesNeeded;
+                    *pcbDecoded = 1 + lenBytes + bytesDecoded;
+                }
+            }
+        }
+    default:
+        FIXME("Unhandled status %u\n", status);
+        SetLastError(CRYPT_E_ASN1_BADTAG);
+        return FALSE;
+    }
+    return ret;
+}
static BOOL CRYPT_AsnDecodeOCSPBasicResponseEntry(const BYTE *pbEncoded, DWORD cbEncoded,
DWORD dwFlags, void *pvStructInfo, DWORD *pcbStructInfo, DWORD *pcbDecoded)
{
@@ -6367,10 +6488,9 @@ static BOOL CRYPT_AsnDecodeOCSPBasicResponseEntry(const BYTE *pbEncoded, DWORD c
     { ASN_INTEGER, offsetof(OCSP_BASIC_RESPONSE_ENTRY, CertId.SerialNumber),
          CRYPT_AsnDecodeIntegerInternal, sizeof(CRYPT_INTEGER_BLOB), FALSE, TRUE,
          offsetof(OCSP_BASIC_RESPONSE_ENTRY, CertId.SerialNumber.pbData), 0 },
-     { ASN_CONTEXT, offsetof(OCSP_BASIC_RESPONSE_ENTRY, dwCertStatus),
-       CRYPT_AsnDecodeIntInternal, sizeof(DWORD), FALSE, FALSE,
-       0, 0 },
-      /* FIXME: pRevokedInfo */
+     { 0, offsetof(OCSP_BASIC_RESPONSE_ENTRY, dwCertStatus),
+       CRYPT_AsnDecodeCertStatus, sizeof(DWORD), FALSE, TRUE,
+       offsetof(OCSP_BASIC_RESPONSE_ENTRY, u.pRevokedInfo), 0 },
     { ASN_GENERALTIME, offsetof(OCSP_BASIC_RESPONSE_ENTRY, ThisUpdate),
          CRYPT_AsnDecodeGeneralizedTime, sizeof(FILETIME), FALSE, FALSE,
          0, 0 },
@@ -6401,13 +6521,13 @@ static BOOL CRYPT_AsnDecodeOCSPBasicResponseEntriesArray(const BYTE *pbEncoded,
     dwFlags, NULL, pvStructInfo, pcbStructInfo, pcbDecoded);
}

-static BOOL CRYPT_AsnDecodeResponderID(const BYTE *pbEncoded,
+static BOOL CRYPT_AsnDecodeResponderIDByName(const BYTE *pbEncoded,
DWORD cbEncoded, DWORD dwFlags, void *pvStructInfo, DWORD *pcbStructInfo,
DWORD *pcbDecoded)
{
     OCSP_BASIC_RESPONSE_INFO *info = pvStructInfo;
-    BYTE tag = pbEncoded[0] & ~3, choice = pbEncoded[0] & 3;
-    DWORD decodedLen, dataLen, lenBytes, bytesNeeded = sizeof(*info), len;
+    DWORD dataLen, decodedLen, lenBytes, bytesNeeded = sizeof(*info);
+    BYTE tag = pbEncoded[0] & ~3;
     CERT_NAME_BLOB *blob;

     if (tag != (ASN_CONTEXT | ASN_CONSTRUCTOR))
@@ -6416,15 +6536,78 @@ static BOOL CRYPT_AsnDecodeResponderID(const BYTE *pbEncoded,
          SetLastError(CRYPT_E_ASN1_BADTAG);
          return FALSE;
     }
-    if (choice > 2)
+    if (!CRYPT_GetLen(pbEncoded, cbEncoded, &dataLen))
+        return FALSE;
+    lenBytes = GET_LEN_BYTES(pbEncoded[1]);
+    cbEncoded -= 1 + lenBytes;
+    if (dataLen > cbEncoded)
-        WARN("Unexpected choice %02x\n", choice);
-        SetLastError(CRYPT_E_ASN1_CORRUPT);
+        SetLastError(CRYPT_E_ASN1_EOD);
+        return FALSE;
+    }
+    pbEncoded += 1 + lenBytes;
+    decodedLen = 1 + lenBytes + dataLen;
+    if (pbEncoded[0] != ASN_SEQUENCE)
+        WARN("Unexpected tag %02x %02x\n", pbEncoded[0], pbEncoded[1]);
+        SetLastError(CRYPT_E_ASN1_BADTAG);
          return FALSE;
     }

+    if (!(dwFlags & CRYPT_DECODE_NOCOPY_FLAG)) bytesNeeded += dataLen;
     if (pvStructInfo && *pcbStructInfo >= bytesNeeded)
-        info->dwResponderIdChoice = choice;
+    {
+        info->dwResponderIdChoice = 1;
+        blob = &info->u.ByNameResponderId;
+        blob->cbData = dataLen;
+        if (dwFlags & CRYPT_DECODE_NOCOPY_FLAG)
+            blob->pbData = (BYTE *)pbEncoded;
+        else if (blob->cbData)
+        {
+            blob->pbData = (BYTE *)(info + 1);
+            memcpy(blob->pbData, pbEncoded, blob->cbData);
+        }
+    }
+    if (pcbDecoded)
+        *pcbDecoded = decodedLen;
+    if (!pvStructInfo)
+        *pcbStructInfo = bytesNeeded;
+        return TRUE;
+    }
+    if (*pcbStructInfo < bytesNeeded)
+        SetLastError(ERROR_MORE_DATA);
+        *pcbStructInfo = bytesNeeded;
+        return FALSE;
+    }
+    *pcbStructInfo = bytesNeeded;
+    return TRUE;
+}
+static BOOL CRYPT_AsnDecodeResponderIDByKey(const BYTE *pbEncoded,
+ DWORD cbEncoded, DWORD dwFlags, void *pvStructInfo, DWORD *pcbStructInfo,
+ DWORD *pcbDecoded)
+{
+    OCSP_BASIC_RESPONSE_INFO *info = pvStructInfo;
+    DWORD dataLen, decodedLen, lenBytes, bytesNeeded = sizeof(*info), len;
+    BYTE tag = pbEncoded[0] & ~3;
+    CRYPT_HASH_BLOB *blob;
+    if (tag != (ASN_CONTEXT | ASN_CONSTRUCTOR))
+        WARN("Unexpected tag %02x\n", tag);
+        SetLastError(CRYPT_E_ASN1_BADTAG);
+        return FALSE;
+    }

     if (!CRYPT_GetLen(pbEncoded, cbEncoded, &dataLen))
          return FALSE;
@@ -6461,7 +6644,8 @@ static BOOL CRYPT_AsnDecodeResponderID(const BYTE *pbEncoded,
     if (!(dwFlags & CRYPT_DECODE_NOCOPY_FLAG)) bytesNeeded += len;
     if (pvStructInfo && *pcbStructInfo >= bytesNeeded)
     {
-        blob = &info->u.ByNameResponderId;
+        info->dwResponderIdChoice = 2;
+        blob = &info->u.ByKeyResponderId;
          blob->cbData = len;
          if (dwFlags & CRYPT_DECODE_NOCOPY_FLAG)
               blob->pbData = (BYTE *)pbEncoded;
@@ -6492,6 +6676,28 @@ static BOOL CRYPT_AsnDecodeResponderID(const BYTE *pbEncoded,
     return TRUE;
}

+static BOOL CRYPT_AsnDecodeResponderID(const BYTE *pbEncoded,
+ DWORD cbEncoded, DWORD dwFlags, void *pvStructInfo, DWORD *pcbStructInfo,
+ DWORD *pcbDecoded)
+{
+    BYTE choice = pbEncoded[0] & 3;
+    TRACE("choice %02x\n", choice);
+    switch (choice)
+    case 1:
+        return CRYPT_AsnDecodeResponderIDByName(pbEncoded, cbEncoded, dwFlags,
+                pvStructInfo, pcbStructInfo, pcbDecoded);
+    case 2:
+        return CRYPT_AsnDecodeResponderIDByKey(pbEncoded, cbEncoded, dwFlags,
+                pvStructInfo, pcbStructInfo, pcbDecoded);
+    default:
+        WARN("Unexpected choice %02x\n", choice);
+        SetLastError(CRYPT_E_ASN1_CORRUPT);
+        return FALSE;
+}
static BOOL WINAPI CRYPT_AsnDecodeOCSPBasicResponse(DWORD dwCertEncodingType,
LPCSTR lpszStructType, const BYTE *pbEncoded, DWORD cbEncoded, DWORD dwFlags,
CRYPT_DECODE_PARA *pDecodePara, void *pvStructInfo, DWORD *pcbStructInfo)
diff --git a/wine/dlls/crypt32/encode.c b/wine/dlls/crypt32/encode.c
index 8086ad2fc..8968eb9f1 100644
--- a/wine/dlls/crypt32/encode.c
+++ b/wine/dlls/crypt32/encode.c
@@ -4500,7 +4500,7 @@ static BOOL WINAPI CRYPT_AsnEncodeCertId(DWORD dwCertEncodingType,
     return ret;
}

-static BOOL WINAPI CRYPT_AsnEncodeOCSPRequestEntry(DWORD dwCertEncodingType,
+static BOOL CRYPT_AsnEncodeOCSPRequestEntry(DWORD dwCertEncodingType,
LPCSTR lpszStructType, const void *pvStructInfo, DWORD dwFlags,
PCRYPT_ENCODE_PARA pEncodePara, BYTE *pbEncoded, DWORD *pcbEncoded)
{
diff --git a/wine/dlls/crypt32/object.c b/wine/dlls/crypt32/object.c
index 8123ed733..4440c9e04 100644
--- a/wine/dlls/crypt32/object.c
+++ b/wine/dlls/crypt32/object.c
@@ -643,7 +643,7 @@ static BOOL CRYPT_QueryEmbeddedMessageObject(DWORD dwObjectType,
          }
          file = CreateFileW(temp_name, GENERIC_READ | GENERIC_WRITE, 0,
               NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_DELETE_ON_CLOSE, NULL);
-        if (file == INVALID_HANDLE_VALUE)
+        if (!file)
          {
               ERR("Could not create temp file.\n");
               SetLastError(ERROR_OUTOFMEMORY);
diff --git a/wine/dlls/crypt32/str.c b/wine/dlls/crypt32/str.c
index 277aeb70d..d74df308e 100644
--- a/wine/dlls/crypt32/str.c
+++ b/wine/dlls/crypt32/str.c
@@ -29,77 +29,45 @@

WINE_DEFAULT_DEBUG_CHANNEL(crypt);

-DWORD WINAPI CertRDNValueToStrA(DWORD dwValueType, PCERT_RDN_VALUE_BLOB pValue,
- LPSTR psz, DWORD csz)
+DWORD WINAPI CertRDNValueToStrA(DWORD type, PCERT_RDN_VALUE_BLOB value_blob,
+                                LPSTR value, DWORD value_len)
{
-    DWORD ret = 0, len;
+    DWORD len, len_mb, ret;
+    LPWSTR valueW;

-    TRACE("(%ld, %p, %p, %ld)\n", dwValueType, pValue, psz, csz);
+    TRACE("(%ld, %p, %p, %ld)\n", type, value_blob, value, value_len);

-    switch (dwValueType)
-    {
-    case CERT_RDN_ANY_TYPE:
-        break;
-    case CERT_RDN_NUMERIC_STRING:
-    case CERT_RDN_PRINTABLE_STRING:
-    case CERT_RDN_TELETEX_STRING:
-    case CERT_RDN_VIDEOTEX_STRING:
-    case CERT_RDN_IA5_STRING:
-    case CERT_RDN_GRAPHIC_STRING:
-    case CERT_RDN_VISIBLE_STRING:
-    case CERT_RDN_GENERAL_STRING:
-        len = pValue->cbData;
-        if (!psz || !csz)
-            ret = len;
-        else
-        {
-            DWORD chars = min(len, csz - 1);
+    len = CertRDNValueToStrW(type, value_blob, NULL, 0);

-            if (chars)
-            {
-                memcpy(psz, pValue->pbData, chars);
-                ret += chars;
-                csz -= chars;
-            }
-        }
-        break;
-    case CERT_RDN_BMP_STRING:
-    case CERT_RDN_UTF8_STRING:
-        len = WideCharToMultiByte(CP_ACP, 0, (LPCWSTR)pValue->pbData,
-         pValue->cbData / sizeof(WCHAR), NULL, 0, NULL, NULL);
-        if (!psz || !csz)
-            ret = len;
-        else
-        {
-            DWORD chars = min(pValue->cbData / sizeof(WCHAR), csz - 1);
+    if (!(valueW = CryptMemAlloc(len * sizeof(*valueW))))
+        ERR("No memory.\n");
+        if (value && value_len) *value = 0;
+        return 1;

-            if (chars)
-            {
-                ret = WideCharToMultiByte(CP_ACP, 0, (LPCWSTR)pValue->pbData,
-                 chars, psz, csz - 1, NULL, NULL);
-                csz -= ret;
-            }
-        }
-        break;
-    default:
-        FIXME("string type %ld unimplemented\n", dwValueType);
+    len = CertRDNValueToStrW(type, value_blob, valueW, len);
+    len_mb = WideCharToMultiByte(CP_ACP, 0, valueW, len, NULL, 0, NULL, NULL);
+    if (!value || !value_len)
+        CryptMemFree(valueW);
+        return len_mb;
-    if (psz && csz)
+    ret = WideCharToMultiByte(CP_ACP, 0, valueW, len, value, value_len, NULL, NULL);
+    if (ret < len_mb)
     {
-        *(psz + ret) = '\0';
-        csz--;
-        ret++;
+        value[0] = 0;
+        ret = 1;
     }
-    else
-        ret++;
-    TRACE("returning %ld (%s)\n", ret, debugstr_a(psz));
+    CryptMemFree(valueW);
     return ret;
}

-DWORD WINAPI CertRDNValueToStrW(DWORD dwValueType, PCERT_RDN_VALUE_BLOB pValue,
- LPWSTR psz, DWORD csz)
+static DWORD rdn_value_to_strW(DWORD dwValueType, PCERT_RDN_VALUE_BLOB pValue,
+                               LPWSTR psz, DWORD csz, BOOL partial_copy)
{
-    DWORD ret = 0, len, i, strLen;
+    DWORD ret = 0, len, i;

     TRACE("(%ld, %p, %p, %ld)\n", dwValueType, pValue, psz, csz);

@@ -116,44 +84,42 @@ DWORD WINAPI CertRDNValueToStrW(DWORD dwValueType, PCERT_RDN_VALUE_BLOB pValue,
     case CERT_RDN_VISIBLE_STRING:
     case CERT_RDN_GENERAL_STRING:
          len = pValue->cbData;
-        if (!psz || !csz)
-            ret = len;
-        else
+        if (!psz || !csz) ret = len;
+        else if (len < csz || partial_copy)
          {
-            WCHAR *ptr = psz;
-
-            for (i = 0; i < pValue->cbData && ptr - psz < csz; ptr++, i++)
-                *ptr = pValue->pbData[i];
-            ret = ptr - psz;
+            len = min(len, csz - 1);
+            for (i = 0; i < len; ++i)
+                psz[i] = pValue->pbData[i];
+            ret = len;
          }
          break;
     case CERT_RDN_BMP_STRING:
     case CERT_RDN_UTF8_STRING:
-        strLen = len = pValue->cbData / sizeof(WCHAR);
+        len = pValue->cbData / sizeof(WCHAR);
          if (!psz || !csz)
               ret = len;
-        else
+        else if (len < csz || partial_copy)
          {
               WCHAR *ptr = psz;

-            for (i = 0; i < strLen && ptr - psz < csz; ptr++, i++)
-                *ptr = ((LPCWSTR)pValue->pbData)[i];
-            ret = ptr - psz;
+            len = min(len, csz - 1);
+            for (i = 0; i < len; ++i)
+                ptr[i] = ((LPCWSTR)pValue->pbData)[i];
+            ret = len;
          }
          break;
     default:
          FIXME("string type %ld unimplemented\n", dwValueType);
     }
-    if (psz && csz)
-    {
-        *(psz + ret) = '\0';
-        csz--;
-        ret++;
-    }
-    else
-        ret++;
-    TRACE("returning %ld (%s)\n", ret, debugstr_w(psz));
-    return ret;
+    if (psz && csz) psz[ret] = 0;
+    TRACE("returning %ld (%s)\n", ret + 1, debugstr_w(psz));
+    return ret + 1;
+}
+DWORD WINAPI CertRDNValueToStrW(DWORD dwValueType, PCERT_RDN_VALUE_BLOB pValue,
+                                LPWSTR psz, DWORD csz)
+    return rdn_value_to_strW(dwValueType, pValue, psz, csz, FALSE);
}

static inline BOOL is_quotable_char(WCHAR c)
@@ -175,115 +141,6 @@ static inline BOOL is_quotable_char(WCHAR c)
     }
}

-static DWORD quote_rdn_value_to_str_a(DWORD dwValueType,
- PCERT_RDN_VALUE_BLOB pValue, LPSTR psz, DWORD csz)
-{
-    DWORD ret = 0, len, i;
-    BOOL needsQuotes = FALSE;
-
-    TRACE("(%ld, %p, %p, %ld)\n", dwValueType, pValue, psz, csz);
-
-    switch (dwValueType)
-    {
-    case CERT_RDN_ANY_TYPE:
-        break;
-    case CERT_RDN_NUMERIC_STRING:
-    case CERT_RDN_PRINTABLE_STRING:
-    case CERT_RDN_TELETEX_STRING:
-    case CERT_RDN_VIDEOTEX_STRING:
-    case CERT_RDN_IA5_STRING:
-    case CERT_RDN_GRAPHIC_STRING:
-    case CERT_RDN_VISIBLE_STRING:
-    case CERT_RDN_GENERAL_STRING:
-        len = pValue->cbData;
-        if (pValue->cbData && isspace(pValue->pbData[0]))
-            needsQuotes = TRUE;
-        if (pValue->cbData && isspace(pValue->pbData[pValue->cbData - 1]))
-            needsQuotes = TRUE;
-        for (i = 0; i < pValue->cbData; i++)
-        {
-            if (is_quotable_char(pValue->pbData[i]))
-                needsQuotes = TRUE;
-            if (pValue->pbData[i] == '"')
-                len += 1;
-        }
-        if (needsQuotes)
-            len += 2;
-        if (!psz || !csz)
-            ret = len;
-        else
-        {
-            char *ptr = psz;
-
-            if (needsQuotes)
-                *ptr++ = '"';
-            for (i = 0; i < pValue->cbData && ptr - psz < csz; ptr++, i++)
-            {
-                *ptr = pValue->pbData[i];
-                if (pValue->pbData[i] == '"' && ptr - psz < csz - 1)
-                    *(++ptr) = '"';
-            }
-            if (needsQuotes && ptr - psz < csz)
-                *ptr++ = '"';
-            ret = ptr - psz;
-        }
-        break;
-    case CERT_RDN_BMP_STRING:
-    case CERT_RDN_UTF8_STRING:
-        len = WideCharToMultiByte(CP_ACP, 0, (LPCWSTR)pValue->pbData,
-         pValue->cbData / sizeof(WCHAR), NULL, 0, NULL, NULL);
-        if (pValue->cbData && iswspace(((LPCWSTR)pValue->pbData)[0]))
-            needsQuotes = TRUE;
-        if (pValue->cbData &&
-         iswspace(((LPCWSTR)pValue->pbData)[pValue->cbData / sizeof(WCHAR)-1]))
-            needsQuotes = TRUE;
-        for (i = 0; i < pValue->cbData / sizeof(WCHAR); i++)
-        {
-            if (is_quotable_char(((LPCWSTR)pValue->pbData)[i]))
-                needsQuotes = TRUE;
-            if (((LPCWSTR)pValue->pbData)[i] == '"')
-                len += 1;
-        }
-        if (needsQuotes)
-            len += 2;
-        if (!psz || !csz)
-            ret = len;
-        else
-        {
-            char *dst = psz;
-
-            if (needsQuotes)
-                *dst++ = '"';
-            for (i = 0; i < pValue->cbData / sizeof(WCHAR) &&
-             dst - psz < csz; dst++, i++)
-            {
-                LPCWSTR src = (LPCWSTR)pValue->pbData + i;
-
-                WideCharToMultiByte(CP_ACP, 0, src, 1, dst,
-                 csz - (dst - psz) - 1, NULL, NULL);
-                if (*src == '"' && dst - psz < csz - 1)
-                    *(++dst) = '"';
-            }
-            if (needsQuotes && dst - psz < csz)
-                *dst++ = '"';
-            ret = dst - psz;
-        }
-        break;
-    default:
-        FIXME("string type %ld unimplemented\n", dwValueType);
-    }
-    if (psz && csz)
-    {
-        *(psz + ret) = '\0';
-        csz--;
-        ret++;
-    }
-    else
-        ret++;
-    TRACE("returning %ld (%s)\n", ret, debugstr_a(psz));
-    return ret;
-}
-
static DWORD quote_rdn_value_to_str_w(DWORD dwValueType,
PCERT_RDN_VALUE_BLOB pValue, LPWSTR psz, DWORD csz)
{
@@ -375,148 +232,41 @@ static DWORD quote_rdn_value_to_str_w(DWORD dwValueType,
     default:
          FIXME("string type %ld unimplemented\n", dwValueType);
     }
-    if (psz && csz)
-    {
-        *(psz + ret) = '\0';
-        csz--;
-        ret++;
-    }
-    else
-        ret++;
     TRACE("returning %ld (%s)\n", ret, debugstr_w(psz));
     return ret;
}

-/* Adds the prefix prefix to the string pointed to by psz, followed by the
- * character '='.  Copies no more than csz characters.  Returns the number of
- * characters copied.  If psz is NULL, returns the number of characters that
- * would be copied.
- */
-static DWORD CRYPT_AddPrefixA(LPCSTR prefix, LPSTR psz, DWORD csz)
+DWORD WINAPI CertNameToStrA(DWORD encoding_type, PCERT_NAME_BLOB name_blob, DWORD str_type, LPSTR str, DWORD str_len)
{
-    DWORD chars;
+    DWORD len, len_mb, ret;
+    LPWSTR strW;

-    TRACE("(%s, %p, %ld)\n", debugstr_a(prefix), psz, csz);
+    TRACE("(%ld, %p, %08lx, %p, %ld)\n", encoding_type, name_blob, str_type, str, str_len);

-    if (psz)
+    len = CertNameToStrW(encoding_type, name_blob, str_type, NULL, 0);
+    if (!(strW = CryptMemAlloc(len * sizeof(*strW))))
     {
-        chars = min(strlen(prefix), csz);
-        memcpy(psz, prefix, chars);
-        *(psz + chars) = '=';
-        chars++;
+        ERR("No memory.\n");
+        if (str && str_len) *str = 0;
+        return 1;
     }
-    else
-        chars = lstrlenA(prefix) + 1;
-    return chars;
-}

-DWORD WINAPI CertNameToStrA(DWORD dwCertEncodingType, PCERT_NAME_BLOB pName,
- DWORD dwStrType, LPSTR psz, DWORD csz)
-{
-    static const DWORD unsupportedFlags = CERT_NAME_STR_NO_QUOTING_FLAG |
-     CERT_NAME_STR_ENABLE_T61_UNICODE_FLAG;
-    static const char commaSep[] = ", ";
-    static const char semiSep[] = "; ";
-    static const char crlfSep[] = "\r\n";
-    static const char plusSep[] = " + ";
-    static const char spaceSep[] = " ";
-    DWORD ret = 0, bytes = 0;
-    BOOL bRet;
-    CERT_NAME_INFO *info;
-
-    TRACE("(%ld, %p, %08lx, %p, %ld)\n", dwCertEncodingType, pName, dwStrType,
-     psz, csz);
-    if (dwStrType & unsupportedFlags)
-        FIXME("unsupported flags: %08lx\n", dwStrType & unsupportedFlags);
-
-    bRet = CryptDecodeObjectEx(dwCertEncodingType, X509_NAME, pName->pbData,
-     pName->cbData, CRYPT_DECODE_ALLOC_FLAG, NULL, &info, &bytes);
-    if (bRet)
+    len = CertNameToStrW(encoding_type, name_blob, str_type, strW, len);
+    len_mb = WideCharToMultiByte(CP_ACP, 0, strW, len, NULL, 0, NULL, NULL);
+    if (!str || !str_len)
     {
-        DWORD i, j, sepLen, rdnSepLen;
-        LPCSTR sep, rdnSep;
-        BOOL reverse = dwStrType & CERT_NAME_STR_REVERSE_FLAG;
-        const CERT_RDN *rdn = info->rgRDN;
-
-        if(reverse && info->cRDN > 1) rdn += (info->cRDN - 1);
-
-        if (dwStrType & CERT_NAME_STR_SEMICOLON_FLAG)
-            sep = semiSep;
-        else if (dwStrType & CERT_NAME_STR_CRLF_FLAG)
-            sep = crlfSep;
-        else
-            sep = commaSep;
-        sepLen = strlen(sep);
-        if (dwStrType & CERT_NAME_STR_NO_PLUS_FLAG)
-            rdnSep = spaceSep;
-        else
-            rdnSep = plusSep;
-        rdnSepLen = strlen(rdnSep);
-        for (i = 0; (!psz || ret < csz) && i < info->cRDN; i++)
-        {
-            for (j = 0; (!psz || ret < csz) && j < rdn->cRDNAttr; j++)
-            {
-                DWORD chars;
-                char prefixBuf[13]; /* big enough for SERIALNUMBER */
-                LPCSTR prefix = NULL;
-
-                if ((dwStrType & 0x000000ff) == CERT_OID_NAME_STR)
-                    prefix = rdn->rgRDNAttr[j].pszObjId;
-                else if ((dwStrType & 0x000000ff) == CERT_X500_NAME_STR)
-                {
-                    PCCRYPT_OID_INFO oidInfo = CryptFindOIDInfo(
-                     CRYPT_OID_INFO_OID_KEY,
-                     rdn->rgRDNAttr[j].pszObjId,
-                     CRYPT_RDN_ATTR_OID_GROUP_ID);
-
-                    if (oidInfo)
-                    {
-                        WideCharToMultiByte(CP_ACP, 0, oidInfo->pwszName, -1,
-                         prefixBuf, sizeof(prefixBuf), NULL, NULL);
-                        prefix = prefixBuf;
-                    }
-                    else
-                        prefix = rdn->rgRDNAttr[j].pszObjId;
-                }
-                if (prefix)
-                {
-                    /* - 1 is needed to account for the NULL terminator. */
-                    chars = CRYPT_AddPrefixA(prefix,
-                     psz ? psz + ret : NULL, psz ? csz - ret - 1 : 0);
-                    ret += chars;
-                }
-                chars = quote_rdn_value_to_str_a(
-                 rdn->rgRDNAttr[j].dwValueType,
-                 &rdn->rgRDNAttr[j].Value, psz ? psz + ret : NULL,
-                 psz ? csz - ret : 0);
-                if (chars)
-                    ret += chars - 1;
-                if (j < rdn->cRDNAttr - 1)
-                {
-                    if (psz && ret < csz - rdnSepLen - 1)
-                        memcpy(psz + ret, rdnSep, rdnSepLen);
-                    ret += rdnSepLen;
-                }
-            }
-            if (i < info->cRDN - 1)
-            {
-                if (psz && ret < csz - sepLen - 1)
-                    memcpy(psz + ret, sep, sepLen);
-                ret += sepLen;
-            }
-            if(reverse) rdn--;
-            else rdn++;
-        }
-        LocalFree(info);
+        CryptMemFree(strW);
+        return len_mb;
     }
-    if (psz && csz)
+
+    ret = WideCharToMultiByte(CP_ACP, 0, strW, len, str, str_len, NULL, NULL);
+    if (ret < len_mb)
     {
-        *(psz + ret) = '\0';
-        ret++;
+        str[0] = 0;
+        ret = 1;
     }
-    else
-        ret++;
-    TRACE("Returning %s\n", debugstr_a(psz));
+    CryptMemFree(strW);
     return ret;
}

@@ -580,6 +330,7 @@ DWORD cert_name_to_str_with_indent(DWORD dwCertEncodingType, DWORD indentLevel,
     DWORD ret = 0, bytes = 0;
     BOOL bRet;
     CERT_NAME_INFO *info;
+    DWORD chars;

     if (dwStrType & unsupportedFlags)
          FIXME("unsupported flags: %08lx\n", dwStrType & unsupportedFlags);
@@ -607,14 +358,17 @@ DWORD cert_name_to_str_with_indent(DWORD dwCertEncodingType, DWORD indentLevel,
          else
               rdnSep = L" + ";
          rdnSepLen = lstrlenW(rdnSep);
-        for (i = 0; (!psz || ret < csz) && i < info->cRDN; i++)
+        if (!csz) psz = NULL;
+        for (i = 0; i < info->cRDN; i++)
          {
-            for (j = 0; (!psz || ret < csz) && j < rdn->cRDNAttr; j++)
+            if (psz && ret + 1 == csz) break;
+            for (j = 0; j < rdn->cRDNAttr; j++)
               {
-                DWORD chars;
               LPCSTR prefixA = NULL;
               LPCWSTR prefixW = NULL;

+                if (psz && ret + 1 == csz) break;
               if ((dwStrType & 0x000000ff) == CERT_OID_NAME_STR)
                    prefixA = rdn->rgRDNAttr[j].pszObjId;
               else if ((dwStrType & 0x000000ff) == CERT_X500_NAME_STR)
@@ -644,6 +398,7 @@ DWORD cert_name_to_str_with_indent(DWORD dwCertEncodingType, DWORD indentLevel,
                              chars = lstrlenW(indent);
                         ret += chars;
                    }
+                    if (psz && ret + 1 == csz) break;
               }
               if (prefixW)
               {
@@ -659,38 +414,40 @@ DWORD cert_name_to_str_with_indent(DWORD dwCertEncodingType, DWORD indentLevel,
                    psz ? psz + ret : NULL, psz ? csz - ret - 1 : 0);
                    ret += chars;
               }
-                chars = quote_rdn_value_to_str_w(
-                 rdn->rgRDNAttr[j].dwValueType,
-                 &rdn->rgRDNAttr[j].Value, psz ? psz + ret : NULL,
-                 psz ? csz - ret : 0);
-                if (chars)
-                    ret += chars - 1;
+                if (psz && ret + 1 == csz) break;
+                chars = quote_rdn_value_to_str_w(rdn->rgRDNAttr[j].dwValueType, &rdn->rgRDNAttr[j].Value,
+                                                 psz ? psz + ret : NULL, psz ? csz - ret - 1 : 0);
+                ret += chars;
               if (j < rdn->cRDNAttr - 1)
               {
-                    if (psz && ret < csz - rdnSepLen - 1)
-                        memcpy(psz + ret, rdnSep, rdnSepLen * sizeof(WCHAR));
-                    ret += rdnSepLen;
+                    if (psz)
+                    {
+                        chars = min(rdnSepLen, csz - ret - 1);
+                        memcpy(psz + ret, rdnSep, chars * sizeof(WCHAR));
+                        ret += chars;
+                    }
+                    else ret += rdnSepLen;
               }
               }
+            if (psz && ret + 1 == csz) break;
               if (i < info->cRDN - 1)
               {
-                if (psz && ret < csz - sepLen - 1)
-                    memcpy(psz + ret, sep, sepLen * sizeof(WCHAR));
-                ret += sepLen;
+                if (psz)
+                {
+                    chars = min(sepLen, csz - ret - 1);
+                    memcpy(psz + ret, sep, chars * sizeof(WCHAR));
+                    ret += chars;
+                }
+                else ret += sepLen;
               }
               if(reverse) rdn--;
               else rdn++;
          }
          LocalFree(info);
     }
-    if (psz && csz)
-    {
-        *(psz + ret) = '\0';
-        ret++;
-    }
-    else
-        ret++;
-    return ret;
+    if (psz && csz) psz[ret] = 0;
+    return ret + 1;
}

DWORD WINAPI CertNameToStrW(DWORD dwCertEncodingType, PCERT_NAME_BLOB pName,
@@ -1113,49 +870,74 @@ BOOL WINAPI CertStrToNameW(DWORD dwCertEncodingType, LPCWSTR pszX500,
     return ret;
}

-DWORD WINAPI CertGetNameStringA(PCCERT_CONTEXT pCertContext, DWORD dwType,
- DWORD dwFlags, void *pvTypePara, LPSTR pszNameString, DWORD cchNameString)
+DWORD WINAPI CertGetNameStringA(PCCERT_CONTEXT cert, DWORD type,
+                                DWORD flags, void *type_para, LPSTR name, DWORD name_len)
{
-    DWORD ret;
+    DWORD len, len_mb, ret;
+    LPWSTR nameW;
+    TRACE("(%p, %ld, %08lx, %p, %p, %ld)\n", cert, type, flags, type_para, name, name_len);

-    TRACE("(%p, %ld, %08lx, %p, %p, %ld)\n", pCertContext, dwType, dwFlags,
-     pvTypePara, pszNameString, cchNameString);
+    len = CertGetNameStringW(cert, type, flags, type_para, NULL, 0);

-    if (pszNameString)
+    if (!(nameW = CryptMemAlloc(len * sizeof(*nameW))))
     {
-        LPWSTR wideName;
-        DWORD nameLen;
+        ERR("No memory.\n");
+        if (name && name_len) *name = 0;
+        return 1;

-        nameLen = CertGetNameStringW(pCertContext, dwType, dwFlags, pvTypePara,
-         NULL, 0);
-        wideName = CryptMemAlloc(nameLen * sizeof(WCHAR));
-        if (wideName)
-        {
-            CertGetNameStringW(pCertContext, dwType, dwFlags, pvTypePara,
-             wideName, nameLen);
-            nameLen = WideCharToMultiByte(CP_ACP, 0, wideName, nameLen,
-             pszNameString, cchNameString, NULL, NULL);
-            if (nameLen <= cchNameString)
-                ret = nameLen;
-            else
-            {
-                pszNameString[cchNameString - 1] = '\0';
-                ret = cchNameString;
-            }
-            CryptMemFree(wideName);
-        }
-        else
-        {
-            *pszNameString = '\0';
-            ret = 1;
-        }
+    len = CertGetNameStringW(cert, type, flags, type_para, nameW, len);
+    len_mb = WideCharToMultiByte(CP_ACP, 0, nameW, len, NULL, 0, NULL, NULL);
+    if (!name || !name_len)
+    {
+        CryptMemFree(nameW);
+        return len_mb;
     }
-    else
-        ret = CertGetNameStringW(pCertContext, dwType, dwFlags, pvTypePara,
-         NULL, 0);
+    ret = WideCharToMultiByte(CP_ACP, 0, nameW, len, name, name_len, NULL, NULL);
+    if (ret < len_mb)
+        name[0] = 0;
+        ret = 1;
+    CryptMemFree(nameW);
     return ret;
}

+static BOOL cert_get_alt_name_info(PCCERT_CONTEXT cert, BOOL alt_name_issuer, PCERT_ALT_NAME_INFO *info)
+    static const char *oids[][2] =
+        { szOID_SUBJECT_ALT_NAME2, szOID_SUBJECT_ALT_NAME },
+        { szOID_ISSUER_ALT_NAME2, szOID_ISSUER_ALT_NAME },
+    PCERT_EXTENSION ext;
+    DWORD bytes = 0;
+    ext = CertFindExtension(oids[!!alt_name_issuer][0], cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension);
+    if (!ext)
+        ext = CertFindExtension(oids[!!alt_name_issuer][1], cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension);
+    if (!ext) return FALSE;
+    return CryptDecodeObjectEx(cert->dwCertEncodingType, X509_ALTERNATE_NAME, ext->Value.pbData, ext->Value.cbData,
+                             CRYPT_DECODE_ALLOC_FLAG, NULL, info, &bytes);
+static PCERT_ALT_NAME_ENTRY cert_find_next_alt_name_entry(PCERT_ALT_NAME_INFO info, DWORD entry_type,
+                                                          unsigned int *index)
+    unsigned int i;
+
+    for (i = *index; i < info->cAltEntry; ++i)
+        if (info->rgAltEntry[i].dwAltNameChoice == entry_type)
+            *index = i + 1;
+            return &info->rgAltEntry[i];
+        }
+    return NULL;
+}
/* Searches cert's extensions for the alternate name extension with OID
* altNameOID, and if found, searches it for the alternate name type entryType.
* If found, returns a pointer to the entry, otherwise returns NULL.
@@ -1165,31 +947,13 @@ DWORD WINAPI CertGetNameStringA(PCCERT_CONTEXT pCertContext, DWORD dwType,
* The return value is a pointer within *info, so don't free *info before
* you're done with the return value.
*/
-static PCERT_ALT_NAME_ENTRY cert_find_alt_name_entry(PCCERT_CONTEXT cert,
- LPCSTR altNameOID, DWORD entryType, PCERT_ALT_NAME_INFO *info)
+static PCERT_ALT_NAME_ENTRY cert_find_alt_name_entry(PCCERT_CONTEXT cert, BOOL alt_name_issuer,
+                                                     DWORD entry_type, PCERT_ALT_NAME_INFO *info)
{
-    PCERT_ALT_NAME_ENTRY entry = NULL;
-    PCERT_EXTENSION ext = CertFindExtension(altNameOID,
-     cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension);
-
-    if (ext)
-    {
-        DWORD bytes = 0;
+    unsigned int index = 0;

-        if (CryptDecodeObjectEx(cert->dwCertEncodingType, X509_ALTERNATE_NAME,
-         ext->Value.pbData, ext->Value.cbData, CRYPT_DECODE_ALLOC_FLAG, NULL,
-         info, &bytes))
-        {
-            DWORD i;
-
-            for (i = 0; !entry && i < (*info)->cAltEntry; i++)
-                if ((*info)->rgAltEntry[i].dwAltNameChoice == entryType)
-                    entry = &(*info)->rgAltEntry[i];
-        }
-    }
-    else
-        *info = NULL;
-    return entry;
+    if (!cert_get_alt_name_info(cert, alt_name_issuer, info)) return NULL;
+    return cert_find_next_alt_name_entry(*info, entry_type, &index);
}

static DWORD cert_get_name_from_rdn_attr(DWORD encodingType,
@@ -1207,222 +971,195 @@ static DWORD cert_get_name_from_rdn_attr(DWORD encodingType,
               oid = szOID_RSA_emailAddr;
          nameAttr = CertFindRDNAttr(oid, nameInfo);
          if (nameAttr)
-            ret = CertRDNValueToStrW(nameAttr->dwValueType, &nameAttr->Value,
-             pszNameString, cchNameString);
+            ret = rdn_value_to_strW(nameAttr->dwValueType, &nameAttr->Value,
+             pszNameString, cchNameString, TRUE);
          LocalFree(nameInfo);
     }
     return ret;
}

-DWORD WINAPI CertGetNameStringW(PCCERT_CONTEXT pCertContext, DWORD dwType,
- DWORD dwFlags, void *pvTypePara, LPWSTR pszNameString, DWORD cchNameString)
+static DWORD copy_output_str(WCHAR *dst, const WCHAR *src, DWORD dst_size)
{
-    DWORD ret = 0;
+    DWORD len = wcslen(src);
+    if (!dst || !dst_size) return len + 1;
+    len = min(len, dst_size - 1);
+    memcpy(dst, src, len * sizeof(*dst));
+    dst[len] = 0;
+    return len + 1;
+DWORD WINAPI CertGetNameStringW(PCCERT_CONTEXT cert, DWORD type, DWORD flags, void *type_para,
+                                LPWSTR name_string, DWORD name_len)
+    static const DWORD supported_flags = CERT_NAME_ISSUER_FLAG | CERT_NAME_SEARCH_ALL_NAMES_FLAG;
+    BOOL alt_name_issuer, search_all_names;
+    CERT_ALT_NAME_INFO *info = NULL;
+    PCERT_ALT_NAME_ENTRY entry;
     PCERT_NAME_BLOB name;
-    LPCSTR altNameOID;
+    DWORD ret = 0;

-    TRACE("(%p, %ld, %08lx, %p, %p, %ld)\n", pCertContext, dwType,
-     dwFlags, pvTypePara, pszNameString, cchNameString);
+    TRACE("(%p, %ld, %08lx, %p, %p, %ld)\n", cert, type, flags, type_para, name_string, name_len);

-    if (!pCertContext)
+    if (!cert)
          goto done;

-    if (dwFlags & CERT_NAME_ISSUER_FLAG)
-    {
-        name = &pCertContext->pCertInfo->Issuer;
-        altNameOID = szOID_ISSUER_ALT_NAME;
-    }
-    else
+    if (flags & ~supported_flags)
+        FIXME("Unsupported flags %#lx.\n", flags);
+    search_all_names = flags & CERT_NAME_SEARCH_ALL_NAMES_FLAG;
+    if (search_all_names && type != CERT_NAME_DNS_TYPE)
     {
-        name = &pCertContext->pCertInfo->Subject;
-        altNameOID = szOID_SUBJECT_ALT_NAME;
+        WARN("CERT_NAME_SEARCH_ALL_NAMES_FLAG used with type %lu.\n", type);
+        goto done;
     }

-    switch (dwType)
+    alt_name_issuer = flags & CERT_NAME_ISSUER_FLAG;
+    name = alt_name_issuer ? &cert->pCertInfo->Issuer : &cert->pCertInfo->Subject;
+    switch (type)
     {
     case CERT_NAME_EMAIL_TYPE:
     {
-        CERT_ALT_NAME_INFO *info;
-        PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-         altNameOID, CERT_ALT_NAME_RFC822_NAME, &info);
+        entry = cert_find_alt_name_entry(cert, alt_name_issuer, CERT_ALT_NAME_RFC822_NAME, &info);

          if (entry)
          {
-            if (!pszNameString)
-                ret = lstrlenW(entry->u.pwszRfc822Name) + 1;
-            else if (cchNameString)
-            {
-                ret = min(lstrlenW(entry->u.pwszRfc822Name), cchNameString - 1);
-                memcpy(pszNameString, entry->u.pwszRfc822Name,
-                 ret * sizeof(WCHAR));
-                pszNameString[ret++] = 0;
-            }
+            ret = copy_output_str(name_string, entry->u.pwszRfc822Name, name_len);
+            break;
          }
-        if (info)
-            LocalFree(info);
-        if (!ret)
-            ret = cert_get_name_from_rdn_attr(pCertContext->dwCertEncodingType,
-             name, szOID_RSA_emailAddr, pszNameString, cchNameString);
+        ret = cert_get_name_from_rdn_attr(cert->dwCertEncodingType, name, szOID_RSA_emailAddr,
+                                          name_string, name_len);
          break;
     }
     case CERT_NAME_RDN_TYPE:
     {
-        DWORD type = pvTypePara ? *(DWORD *)pvTypePara : 0;
+        DWORD param = type_para ? *(DWORD *)type_para : 0;

          if (name->cbData)
-            ret = CertNameToStrW(pCertContext->dwCertEncodingType, name,
-             type, pszNameString, cchNameString);
+        {
+            ret = CertNameToStrW(cert->dwCertEncodingType, name, param, name_string, name_len);
+        }
          else
          {
-            CERT_ALT_NAME_INFO *info;
-            PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-             altNameOID, CERT_ALT_NAME_DIRECTORY_NAME, &info);
+            entry = cert_find_alt_name_entry(cert, alt_name_issuer, CERT_ALT_NAME_DIRECTORY_NAME, &info);

               if (entry)
-                ret = CertNameToStrW(pCertContext->dwCertEncodingType,
-                 &entry->u.DirectoryName, type, pszNameString, cchNameString);
-            if (info)
-                LocalFree(info);
+                ret = CertNameToStrW(cert->dwCertEncodingType, &entry->u.DirectoryName,
+                                     param, name_string, name_len);
          }
          break;
     }
     case CERT_NAME_ATTR_TYPE:
-        ret = cert_get_name_from_rdn_attr(pCertContext->dwCertEncodingType,
-         name, pvTypePara, pszNameString, cchNameString);
-        if (!ret)
-        {
-            CERT_ALT_NAME_INFO *altInfo;
-            PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-             altNameOID, CERT_ALT_NAME_DIRECTORY_NAME, &altInfo);
+        ret = cert_get_name_from_rdn_attr(cert->dwCertEncodingType, name, type_para,
+                                          name_string, name_len);
+        if (ret) break;

-            if (entry)
-                ret = cert_name_to_str_with_indent(X509_ASN_ENCODING, 0,
-                 &entry->u.DirectoryName, 0, pszNameString, cchNameString);
-            if (altInfo)
-                LocalFree(altInfo);
-        }
+        entry = cert_find_alt_name_entry(cert, alt_name_issuer, CERT_ALT_NAME_DIRECTORY_NAME, &info);
+        if (entry)
+            ret = cert_name_to_str_with_indent(X509_ASN_ENCODING, 0, &entry->u.DirectoryName,
+                                               0, name_string, name_len);
          break;
     case CERT_NAME_SIMPLE_DISPLAY_TYPE:
     {
-        static const LPCSTR simpleAttributeOIDs[] = { szOID_COMMON_NAME,
-         szOID_ORGANIZATIONAL_UNIT_NAME, szOID_ORGANIZATION_NAME,
-         szOID_RSA_emailAddr };
+        static const LPCSTR simpleAttributeOIDs[] =
+        {
+            szOID_COMMON_NAME, szOID_ORGANIZATIONAL_UNIT_NAME, szOID_ORGANIZATION_NAME, szOID_RSA_emailAddr
+        };
          CERT_NAME_INFO *nameInfo = NULL;
          DWORD bytes = 0, i;

-        if (CryptDecodeObjectEx(pCertContext->dwCertEncodingType, X509_NAME,
-         name->pbData, name->cbData, CRYPT_DECODE_ALLOC_FLAG, NULL, &nameInfo,
-         &bytes))
+        if (CryptDecodeObjectEx(cert->dwCertEncodingType, X509_NAME, name->pbData, name->cbData,
+                                CRYPT_DECODE_ALLOC_FLAG, NULL, &nameInfo, &bytes))
          {
               PCERT_RDN_ATTR nameAttr = NULL;

               for (i = 0; !nameAttr && i < ARRAY_SIZE(simpleAttributeOIDs); i++)
               nameAttr = CertFindRDNAttr(simpleAttributeOIDs[i], nameInfo);
               if (nameAttr)
-                ret = CertRDNValueToStrW(nameAttr->dwValueType,
-                 &nameAttr->Value, pszNameString, cchNameString);
+                ret = rdn_value_to_strW(nameAttr->dwValueType, &nameAttr->Value, name_string, name_len, TRUE);
               LocalFree(nameInfo);
          }
-        if (!ret)
-        {
-            CERT_ALT_NAME_INFO *altInfo;
-            PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-             altNameOID, CERT_ALT_NAME_RFC822_NAME, &altInfo);
-
-            if (altInfo)
-            {
-                if (!entry && altInfo->cAltEntry)
-                    entry = &altInfo->rgAltEntry[0];
-                if (entry)
-                {
-                    if (!pszNameString)
-                        ret = lstrlenW(entry->u.pwszRfc822Name) + 1;
-                    else if (cchNameString)
-                    {
-                        ret = min(lstrlenW(entry->u.pwszRfc822Name),
-                         cchNameString - 1);
-                        memcpy(pszNameString, entry->u.pwszRfc822Name,
-                         ret * sizeof(WCHAR));
-                        pszNameString[ret++] = 0;
-                    }
-                }
-                LocalFree(altInfo);
-            }
-        }
+        if (ret) break;
+        entry = cert_find_alt_name_entry(cert, alt_name_issuer, CERT_ALT_NAME_RFC822_NAME, &info);
+        if (!info) break;
+        if (!entry && info->cAltEntry)
+            entry = &info->rgAltEntry[0];
+        if (entry) ret = copy_output_str(name_string, entry->u.pwszRfc822Name, name_len);
          break;
     }
     case CERT_NAME_FRIENDLY_DISPLAY_TYPE:
     {
-        DWORD cch = cchNameString;
+        DWORD len = name_len;

-        if (CertGetCertificateContextProperty(pCertContext,
-         CERT_FRIENDLY_NAME_PROP_ID, pszNameString, &cch))
-            ret = cch;
+        if (CertGetCertificateContextProperty(cert, CERT_FRIENDLY_NAME_PROP_ID, name_string, &len))
+            ret = len;
          else
-            ret = CertGetNameStringW(pCertContext,
-             CERT_NAME_SIMPLE_DISPLAY_TYPE, dwFlags, pvTypePara, pszNameString,
-             cchNameString);
+            ret = CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, flags,
+                                     type_para, name_string, name_len);
          break;
     }
     case CERT_NAME_DNS_TYPE:
     {
-        CERT_ALT_NAME_INFO *info;
-        PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-         altNameOID, CERT_ALT_NAME_DNS_NAME, &info);
+        unsigned int index = 0, len;

-        if (entry)
+        if (cert_get_alt_name_info(cert, alt_name_issuer, &info)
+            && (entry = cert_find_next_alt_name_entry(info, CERT_ALT_NAME_DNS_NAME, &index)))
          {
-            if (!pszNameString)
-                ret = lstrlenW(entry->u.pwszDNSName) + 1;
-            else if (cchNameString)
+            if (search_all_names)
               {
-                ret = min(lstrlenW(entry->u.pwszDNSName), cchNameString - 1);
-                memcpy(pszNameString, entry->u.pwszDNSName, ret * sizeof(WCHAR));
-                pszNameString[ret++] = 0;
+                do
+                {
+                    if (name_string && name_len == 1) break;
+                    ret += len = copy_output_str(name_string, entry->u.pwszDNSName, name_len ? name_len - 1 : 0);
+                    if (name_string && name_len)
+                    {
+                        name_string += len;
+                        name_len -= len;
+                    }
+                }
+                while ((entry = cert_find_next_alt_name_entry(info, CERT_ALT_NAME_DNS_NAME, &index)));
               }
+            else ret = copy_output_str(name_string, entry->u.pwszDNSName, name_len);
          }
-        if (info)
-            LocalFree(info);
-        if (!ret)
-            ret = cert_get_name_from_rdn_attr(pCertContext->dwCertEncodingType,
-             name, szOID_COMMON_NAME, pszNameString, cchNameString);
-        break;
-    }
-    case CERT_NAME_URL_TYPE:
-    {
-        CERT_ALT_NAME_INFO *info;
-        PCERT_ALT_NAME_ENTRY entry = cert_find_alt_name_entry(pCertContext,
-         altNameOID, CERT_ALT_NAME_URL, &info);
-
-        if (entry)
+        else
          {
-            if (!pszNameString)
-                ret = lstrlenW(entry->u.pwszURL) + 1;
-            else if (cchNameString)
+            if (!search_all_names || name_len != 1)
               {
-                ret = min(lstrlenW(entry->u.pwszURL), cchNameString - 1);
-                memcpy(pszNameString, entry->u.pwszURL, ret * sizeof(WCHAR));
-                pszNameString[ret++] = 0;
+                len = search_all_names && name_len ? name_len - 1 : name_len;
+                ret = cert_get_name_from_rdn_attr(cert->dwCertEncodingType, name, szOID_COMMON_NAME,
+                                                  name_string, len);
+                if (name_string) name_string += ret;
               }
          }
-        if (info)
-            LocalFree(info);
+        if (search_all_names)
+        {
+            if (name_string && name_len) *name_string = 0;
+            ++ret;
+        }
+        break;
+    case CERT_NAME_URL_TYPE:
+    {
+        if ((entry = cert_find_alt_name_entry(cert, alt_name_issuer, CERT_ALT_NAME_URL, &info)))
+            ret = copy_output_str(name_string, entry->u.pwszURL, name_len);
          break;
     }
     default:
-        FIXME("unimplemented for type %ld\n", dwType);
+        FIXME("unimplemented for type %lu.\n", type);
          ret = 0;
+        break;
     }
done:
+    if (info)
+        LocalFree(info);
     if (!ret)
     {
-        if (!pszNameString)
-            ret = 1;
-        else if (cchNameString)
-        {
-            pszNameString[0] = 0;
-            ret = 1;
-        }
+        ret = 1;
+        if (name_string && name_len) name_string[0] = 0;
     }
     return ret;
}
diff --git a/wine/dlls/crypt32/tests/base64.c b/wine/dlls/crypt32/tests/base64.c
index a1517b294..e81a57c57 100644
--- a/wine/dlls/crypt32/tests/base64.c
+++ b/wine/dlls/crypt32/tests/base64.c
@@ -23,7 +23,6 @@
#include <windows.h>
#include <wincrypt.h>

-#include "wine/heap.h"
#include "wine/test.h"

#define CERT_HEADER               "-----BEGIN CERTIFICATE-----\r\n"
@@ -93,7 +92,7 @@ static WCHAR *strdupAtoW(const char *str)

     if (!str) return ret;
     len = MultiByteToWideChar(CP_ACP, 0, str, -1, NULL, 0);
-    ret = heap_alloc(len * sizeof(WCHAR));
+    ret = malloc(len * sizeof(WCHAR));
     if (ret)
          MultiByteToWideChar(CP_ACP, 0, str, -1, ret, len);
     return ret;
@@ -128,7 +127,7 @@ static void encodeAndCompareBase64_A(const BYTE *toEncode, DWORD toEncodeLen,
     ok(ret, "CryptBinaryToStringA failed: %ld\n", GetLastError());
     ok(strLen == strLen2, "Unexpected required length %lu, expected %lu.\n", strLen2, strLen);

-    str = heap_alloc(strLen);
+    str = malloc(strLen);

     /* Partially filled output buffer. */
     strLen2 = strLen - 1;
@@ -157,7 +156,7 @@ static void encodeAndCompareBase64_A(const BYTE *toEncode, DWORD toEncodeLen,
     if (trailer)
          ok(!strncmp(trailer, ptr, strlen(trailer)), "Expected trailer %s, got %s\n", trailer, ptr);

-    heap_free(str);
+    free(str);
}

static void encode_compare_base64_W(const BYTE *toEncode, DWORD toEncodeLen, DWORD format,
@@ -196,7 +195,7 @@ static void encode_compare_base64_W(const BYTE *toEncode, DWORD toEncodeLen, DWO
     ok(ret, "CryptBinaryToStringW failed: %ld\n", GetLastError());
     ok(strLen == strLen2, "Unexpected required length.\n");

-    strW = heap_alloc(strLen * sizeof(WCHAR));
+    strW = malloc(strLen * sizeof(WCHAR));

     headerW = strdupAtoW(header);
     trailerW = strdupAtoW(trailer);
@@ -231,9 +230,9 @@ static void encode_compare_base64_W(const BYTE *toEncode, DWORD toEncodeLen, DWO
          ok(!memcmp(trailerW, ptr, lstrlenW(trailerW)), "Expected trailer %s, got %s.\n", wine_dbgstr_w(trailerW),
               wine_dbgstr_w(ptr));

-    heap_free(strW);
-    heap_free(headerW);
-    heap_free(trailerW);
+    free(strW);
+    free(headerW);
+    free(trailerW);
}

static DWORD binary_to_hex_len(DWORD binary_len, DWORD flags)
@@ -267,6 +266,7 @@ static void test_CryptBinaryToString(void)
     BYTE input[256 * sizeof(WCHAR)];
     DWORD strLen, strLen2, i, j, k;
     WCHAR *hex, *cmp, *ptr;
+    char *hex_a, *cmp_a;
     BOOL ret;

     ret = CryptBinaryToStringA(NULL, 0, 0, NULL, NULL);
@@ -299,12 +299,12 @@ static void test_CryptBinaryToString(void)
          ok(strLen == tests[i].toEncodeLen, "Unexpected required length %lu.\n", strLen);

          strLen2 = strLen;
-        str = heap_alloc(strLen);
+        str = malloc(strLen);
          ret = CryptBinaryToStringA(tests[i].toEncode, tests[i].toEncodeLen, CRYPT_STRING_BINARY, str, &strLen2);
          ok(ret, "CryptBinaryToStringA failed: %ld\n", GetLastError());
          ok(strLen == strLen2, "Expected length %lu, got %lu\n", strLen, strLen2);
          ok(!memcmp(str, tests[i].toEncode, tests[i].toEncodeLen), "Unexpected value\n");
-        heap_free(str);
+        free(str);

          strLen = 0;
          ret = CryptBinaryToStringW(tests[i].toEncode, tests[i].toEncodeLen, CRYPT_STRING_BINARY, NULL, &strLen);
@@ -312,12 +312,12 @@ static void test_CryptBinaryToString(void)
          ok(strLen == tests[i].toEncodeLen, "Unexpected required length %lu.\n", strLen);

          strLen2 = strLen;
-        strW = heap_alloc(strLen);
+        strW = malloc(strLen);
          ret = CryptBinaryToStringW(tests[i].toEncode, tests[i].toEncodeLen, CRYPT_STRING_BINARY, strW, &strLen2);
          ok(ret, "CryptBinaryToStringW failed: %ld\n", GetLastError());
          ok(strLen == strLen2, "Expected length %lu, got %lu\n", strLen, strLen2);
          ok(!memcmp(strW, tests[i].toEncode, tests[i].toEncodeLen), "Unexpected value\n");
-        heap_free(strW);
+        free(strW);

          encodeAndCompareBase64_A(tests[i].toEncode, tests[i].toEncodeLen, CRYPT_STRING_BASE64,
               tests[i].base64, NULL, NULL);
@@ -338,7 +338,7 @@ static void test_CryptBinaryToString(void)
          encode_compare_base64_W(tests[i].toEncode, tests[i].toEncodeLen, CRYPT_STRING_BASE64X509CRLHEADER, encodedW,
               X509_HEADER, X509_TRAILER);

-        heap_free(encodedW);
+        free(encodedW);
     }

     for (i = 0; i < ARRAY_SIZE(testsNoCR); i++)
@@ -352,13 +352,13 @@ static void test_CryptBinaryToString(void)
          ok(ret, "CryptBinaryToStringA failed: %ld\n", GetLastError());

          strLen2 = strLen;
-        str = heap_alloc(strLen);
+        str = malloc(strLen);
          ret = CryptBinaryToStringA(testsNoCR[i].toEncode, testsNoCR[i].toEncodeLen,
               CRYPT_STRING_BINARY | CRYPT_STRING_NOCR, str, &strLen2);
          ok(ret, "CryptBinaryToStringA failed: %ld\n", GetLastError());
          ok(strLen == strLen2, "Expected length %ld, got %ld\n", strLen, strLen2);
          ok(!memcmp(str, testsNoCR[i].toEncode, testsNoCR[i].toEncodeLen), "Unexpected value\n");
-        heap_free(str);
+        free(str);

          encodeAndCompareBase64_A(testsNoCR[i].toEncode, testsNoCR[i].toEncodeLen, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCR,
               testsNoCR[i].base64, NULL, NULL);
@@ -383,7 +383,7 @@ static void test_CryptBinaryToString(void)
               CRYPT_STRING_BASE64X509CRLHEADER | CRYPT_STRING_NOCR, encodedW,
               X509_HEADER_NOCR, X509_TRAILER_NOCR);

-        heap_free(encodedW);
+        free(encodedW);
     }

     /* Systems that don't support HEXRAW format convert to BASE64 instead - 3 bytes in -> 4 chars + crlf + 1 null out. */
@@ -402,11 +402,17 @@ static void test_CryptBinaryToString(void)

     for (i = 0; i < ARRAY_SIZE(flags); i++)
     {
+        winetest_push_context("i %lu", i);
          strLen = 0;
          ret = CryptBinaryToStringW(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i], NULL, &strLen);
          ok(ret, "CryptBinaryToStringW failed: %ld\n", GetLastError());
          ok(strLen > 0, "Unexpected string length.\n");

+        strLen = 0;
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i], NULL, &strLen);
+        ok(ret, "failed, error %ld.\n", GetLastError());
+        ok(strLen > 0, "Unexpected string length.\n");
          strLen = ~0;
          ret = CryptBinaryToStringW(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i],
                                   NULL, &strLen);
@@ -420,9 +426,12 @@ static void test_CryptBinaryToString(void)
          strLen2 += sizeof(input) * 2 + 1;
          ok(strLen == strLen2, "Expected length %ld, got %ld\n", strLen2, strLen);

-        hex = heap_alloc(strLen * sizeof(WCHAR));
+        hex = malloc(strLen * sizeof(WCHAR));
+        hex_a = malloc(strLen);
          memset(hex, 0xcc, strLen * sizeof(WCHAR));
-        ptr = cmp = heap_alloc(strLen * sizeof(WCHAR));
+        ptr = cmp = malloc(strLen * sizeof(WCHAR));
+        cmp_a = malloc(strLen);
          for (j = 0; j < ARRAY_SIZE(input); j++)
          {
               *ptr++ = hexdig[(input[j] >> 4) & 0xf];
@@ -438,6 +447,11 @@ static void test_CryptBinaryToString(void)
               *ptr++ = '\n';
          }
          *ptr++ = 0;
+        for (j = 0; cmp[j]; ++j)
+            cmp_a[j] = cmp[j];
+        cmp_a[j] = 0;
          ret = CryptBinaryToStringW(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i],
                                   hex, &strLen);
          ok(ret, "CryptBinaryToStringW failed: %ld\n", GetLastError());
@@ -445,6 +459,13 @@ static void test_CryptBinaryToString(void)
          ok(strLen == strLen2, "Expected length %ld, got %ld\n", strLen, strLen2);
          ok(!memcmp(hex, cmp, strLen * sizeof(WCHAR)), "Unexpected value\n");

+        ++strLen;
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW | flags[i],
+                                   hex_a, &strLen);
+        ok(ret, "failed, error %ld.\n", GetLastError());
+        ok(strLen == strLen2, "Expected length %ld, got %ld.\n", strLen, strLen2);
+        ok(!memcmp(hex_a, cmp_a, strLen), "Unexpected value.\n");
          /* adjusts size if buffer too big */
          strLen *= 2;
          ret = CryptBinaryToStringW(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i],
@@ -452,6 +473,12 @@ static void test_CryptBinaryToString(void)
          ok(ret, "CryptBinaryToStringW failed: %ld\n", GetLastError());
          ok(strLen == strLen2, "Expected length %ld, got %ld\n", strLen, strLen2);

+        strLen *= 2;
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW|flags[i],
+                                   hex_a, &strLen);
+        ok(ret, "failed, error %ld.\n", GetLastError());
+        ok(strLen == strLen2, "Expected length %ld, got %ld.\n", strLen, strLen2);
          /* no writes if buffer too small */
          strLen /= 2;
          strLen2 /= 2;
@@ -465,8 +492,49 @@ static void test_CryptBinaryToString(void)
          ok(strLen == strLen2, "Expected length %ld, got %ld\n", strLen, strLen2);
          ok(!memcmp(hex, cmp, strLen * sizeof(WCHAR)), "Unexpected value\n");

-        heap_free(hex);
-        heap_free(cmp);
+        SetLastError(0xdeadbeef);
+        memset(hex_a, 0xcc, strLen + 3);
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW | flags[i],
+                                   hex_a, &strLen);
+        ok(!ret && GetLastError() == ERROR_MORE_DATA,"got ret %d, error %lu.\n", ret, GetLastError());
+        ok(strLen == strLen2, "Expected length %ld, got %ld.\n", strLen2, strLen);
+        /* Output consists of the number of full bytes which fit in plus terminating 0. */
+        strLen = (strLen - 1) & ~1;
+        ok(!memcmp(hex_a, cmp_a, strLen), "Unexpected value\n");
+        ok(!hex_a[strLen], "got %#x.\n", (unsigned char)hex_a[strLen]);
+        ok((unsigned char)hex_a[strLen + 1] == 0xcc, "got %#x.\n", (unsigned char)hex_a[strLen + 1]);
+        /* Output is not filled if string length is less than 3. */
+        strLen = 1;
+        memset(hex_a, 0xcc, strLen2);
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW | flags[i],
+                                   hex_a, &strLen);
+        ok(strLen == 1, "got %ld.\n", strLen);
+        ok((unsigned char)hex_a[0] == 0xcc, "got %#x.\n", (unsigned char)hex_a[strLen - 1]);
+        strLen = 2;
+        memset(hex_a, 0xcc, strLen2);
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW | flags[i],
+                                   hex_a, &strLen);
+        ok(strLen == 2, "got %ld.\n", strLen);
+        ok((unsigned char)hex_a[0] == 0xcc, "got %#x.\n", (unsigned char)hex_a[0]);
+        ok((unsigned char)hex_a[1] == 0xcc, "got %#x.\n", (unsigned char)hex_a[1]);
+        strLen = 3;
+        memset(hex_a, 0xcc, strLen2);
+        ret = CryptBinaryToStringA(input, sizeof(input), CRYPT_STRING_HEXRAW | flags[i],
+                                   hex_a, &strLen);
+        ok(strLen == 3, "got %ld.\n", strLen);
+        ok(hex_a[0] == 0x30, "got %#x.\n", (unsigned char)hex_a[0]);
+        ok(hex_a[1] == 0x30, "got %#x.\n", (unsigned char)hex_a[1]);
+        ok(!hex_a[2], "got %#x.\n", (unsigned char)hex_a[2]);
+        free(hex);
+        free(hex_a);
+        free(cmp);
+        free(cmp_a);
+        winetest_pop_context();

     for (k = 0; k < ARRAY_SIZE(sizes); k++)
@@ -483,10 +551,10 @@ static void test_CryptBinaryToString(void)
          strLen2 = binary_to_hex_len(sizes[k], CRYPT_STRING_HEX | flags[i]);
          ok(strLen == strLen2, "%lu: Expected length %ld, got %ld\n", i, strLen2, strLen);

-        hex = heap_alloc(strLen * sizeof(WCHAR) + 256);
+        hex = malloc(strLen * sizeof(WCHAR) + 256);
          memset(hex, 0xcc, strLen * sizeof(WCHAR));

-        ptr = cmp = heap_alloc(strLen * sizeof(WCHAR) + 256);
+        ptr = cmp = malloc(strLen * sizeof(WCHAR) + 256);
          for (j = 0; j < sizes[k]; j++)
          {
               *ptr++ = hexdig[(input[j] >> 4) & 0xf];
@@ -552,8 +620,8 @@ static void test_CryptBinaryToString(void)
          ok(strLen == strLen2, "%lu: Expected length %ld, got %ld\n", i, strLen, strLen2);
          ok(!memcmp(hex, cmp, strLen * sizeof(WCHAR)), "%lu: got %s\n", i, wine_dbgstr_wn(hex, strLen));

-        heap_free(hex);
-        heap_free(cmp);
+        free(hex);
+        free(cmp);
}

@@ -569,7 +637,7 @@ static void decodeAndCompareBase64_A(LPCSTR toDecode, LPCSTR header,
          len += strlen(header);
     if (trailer)
          len += strlen(trailer);
-    str = HeapAlloc(GetProcessHeap(), 0, len);
+    str = malloc(len);
     if (str)
     {
          LPBYTE buf;
@@ -586,7 +654,7 @@ static void decodeAndCompareBase64_A(LPCSTR toDecode, LPCSTR header,
          ret = CryptStringToBinaryA(str, 0, useFormat, NULL, &bufLen, NULL,
          NULL);
          ok(ret, "CryptStringToBinaryA failed: %ld\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufLen);
+        buf = malloc(bufLen);
          if (buf)
          {
               DWORD skipped, usedFormat;
@@ -605,7 +673,7 @@ static void decodeAndCompareBase64_A(LPCSTR toDecode, LPCSTR header,
               ok(skipped == 0, "Expected skipped 0, got %ld\n", skipped);
               ok(usedFormat == expectedFormat, "Expected format %ld, got %ld\n",
               expectedFormat, usedFormat);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }

          /* Check again, but with garbage up front */
@@ -625,7 +693,7 @@ static void decodeAndCompareBase64_A(LPCSTR toDecode, LPCSTR header,
               "Expected !ret and last error ERROR_INVALID_DATA, got ret=%d, error=%ld\n", ret, GetLastError());
          if (ret)
          {
-            buf = HeapAlloc(GetProcessHeap(), 0, bufLen);
+            buf = malloc(bufLen);
               if (buf)
               {
               DWORD skipped, usedFormat;
@@ -636,10 +704,10 @@ static void decodeAndCompareBase64_A(LPCSTR toDecode, LPCSTR header,
               ok(skipped == strlen(garbage),
                    "Expected %d characters of \"%s\" skipped when trying format %08lx, got %ld (used format is %08lx)\n",
                    lstrlenA(garbage), str, useFormat, skipped, usedFormat);
-                HeapFree(GetProcessHeap(), 0, buf);
+                free(buf);
               }
          }
-        HeapFree(GetProcessHeap(), 0, str);
+        free(str);
}

@@ -707,11 +775,145 @@ static const struct BadString badStrings[] = {
{ "-----BEGIN X509 CRL-----\r\nAA==\r\n", CRYPT_STRING_BASE64X509CRLHEADER },
};

-static void testStringToBinaryA(void)
+static BOOL is_hex_string_special_char(WCHAR c)
{
-    BOOL ret;
+    switch (c)
+        case '-':
+        case ',':
+        case ' ':
+        case '\t':
+        case '\r':
+        case '\n':
+            return TRUE;
+        default:
+            return FALSE;
+}
+static WCHAR wchar_from_str(BOOL wide, const void **str, DWORD *len)
+{
+    WCHAR c;
+    if (!*len)
+        return 0;
+    --*len;
+    if (wide)
+        c = *(*(const WCHAR **)str)++;
+    else
+        c = *(*(const char **)str)++;
+    return c ? c : 0xffff;
+}
+static BYTE digit_from_char(WCHAR c)
+{
+    if (c >= '0' && c <= '9')
+        return c - '0';
+    c = towlower(c);
+    if (c >= 'a' && c <= 'f')
+        return c - 'a' + 0xa;
+    return 0xff;
+}
+static LONG string_to_hex(const void* str, BOOL wide, DWORD len, BYTE *hex, DWORD *hex_len,
+        DWORD *skipped, DWORD *ret_flags)
+{
+    unsigned int byte_idx = 0;
+    BYTE d1, d2;
+    WCHAR c;
+    if (!str || !hex_len)
+        return ERROR_INVALID_PARAMETER;
+    if (!len)
+        len = wide ? wcslen(str) : strlen(str);
+    if (wide && !len)
+        return ERROR_INVALID_PARAMETER;
+    if (skipped)
+        *skipped = 0;
+    if (ret_flags)
+        *ret_flags = 0;
+    while ((c = wchar_from_str(wide, &str, &len)) && is_hex_string_special_char(c))
+        ;
+    while ((d1 = digit_from_char(c)) != 0xff)
+        if ((d2 = digit_from_char(wchar_from_str(wide, &str, &len))) == 0xff)
+        {
+            if (!hex)
+                *hex_len = 0;
+            return ERROR_INVALID_DATA;
+        }
+
+        if (hex && byte_idx < *hex_len)
+            hex[byte_idx] = (d1 << 4) | d2;
+
+        ++byte_idx;
+
+        do
+        {
+            c = wchar_from_str(wide, &str, &len);
+        } while (c == '-' || c == ',');
+    while (c)
+        if (!is_hex_string_special_char(c))
+        {
+            if (!hex)
+                *hex_len = 0;
+            return ERROR_INVALID_DATA;
+        }
+        c = wchar_from_str(wide, &str, &len);
+    if (hex && byte_idx > *hex_len)
+        return ERROR_MORE_DATA;
+
+    if (ret_flags)
+        *ret_flags = CRYPT_STRING_HEX;
+
+    *hex_len = byte_idx;
+static void test_CryptStringToBinary(void)
+    static const char *string_hex_tests[] =
+    {
+        "",
+        "-",
+        ",-",
+        "0",
+        "00",
+        "000",
+        "11220",
+        "1122q",
+        "q1122",
+        " aE\t\n\r\n",
+        "01-02",
+        "-,01-02",
+        "01-02-",
+        "aa,BB-ff,-,",
+        "1-2",
+        "010-02",
+        "aa,BBff,-,",
+        "aa,,-BB---ff,-,",
+        "010203040506070809q",
+    };
+    DWORD skipped, flags, expected_err, expected_len, expected_skipped, expected_flags;
+    BYTE buf[8], expected[8];
     DWORD bufLen = 0, i;
-    BYTE buf[8];
+    WCHAR str_w[64];
+    BOOL ret, wide;

     ret = CryptStringToBinaryA(NULL, 0, 0, NULL, NULL, NULL, NULL);
     ok(!ret && GetLastError() == ERROR_INVALID_PARAMETER,
@@ -891,10 +1093,254 @@ static void testStringToBinaryA(void)
          CRYPT_STRING_ANY, CRYPT_STRING_BASE64HEADER, testsNoCR[i].toEncode,
          testsNoCR[i].toEncodeLen);
     }
+    /* CRYPT_STRING_HEX */
+    ret = CryptStringToBinaryW(L"01", 2, CRYPT_STRING_HEX, NULL, NULL, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_PARAMETER, "got ret %d, error %lu.\n", ret, GetLastError());
+    if (0)
+    {
+        /* access violation on Windows. */
+        CryptStringToBinaryA("01", 2, CRYPT_STRING_HEX, NULL, NULL, NULL, NULL);
+    }
+    bufLen = 8;
+    ret = CryptStringToBinaryW(L"0102", 2, CRYPT_STRING_HEX, NULL, &bufLen, NULL, NULL);
+    ok(ret, "got error %lu.\n", GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    bufLen = 8;
+    ret = CryptStringToBinaryW(NULL, 0, CRYPT_STRING_HEX, NULL, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_PARAMETER, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 8, "got length %lu.\n", bufLen);
+    bufLen = 8;
+    ret = CryptStringToBinaryA(NULL, 0, CRYPT_STRING_HEX, NULL, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_PARAMETER, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 8, "got length %lu.\n", bufLen);
+    bufLen = 8;
+    ret = CryptStringToBinaryW(L"0102", 3, CRYPT_STRING_HEX, NULL, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(!bufLen, "got length %lu.\n", bufLen);
+    bufLen = 8;
+    buf[0] = 0xcc;
+    ret = CryptStringToBinaryW(L"0102", 3, CRYPT_STRING_HEX, buf, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 8, "got length %lu.\n", bufLen);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    bufLen = 8;
+    buf[0] = 0xcc;
+    ret = CryptStringToBinaryW(L"0102", 2, CRYPT_STRING_HEX, buf, &bufLen, NULL, NULL);
+    ok(ret, "got error %lu.\n", GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    bufLen = 8;
+    buf[0] = buf[1] = 0xcc;
+    ret = CryptStringToBinaryA("01\0 02", 4, CRYPT_STRING_HEX, buf, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 8, "got length %lu.\n", bufLen);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    bufLen = 8;
+    buf[0] = buf[1] = 0xcc;
+    ret = CryptStringToBinaryW(L"01\0 02", 4, CRYPT_STRING_HEX, buf, &bufLen, NULL, NULL);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 8, "got length %lu.\n", bufLen);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    bufLen = 1;
+    buf[0] = 0xcc;
+    skipped = 0xdeadbeef;
+    flags = 0xdeadbeef;
+    ret = CryptStringToBinaryW(L"0102", 4, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+    ok(!ret && GetLastError() == ERROR_MORE_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(!flags, "got flags %lu.\n", flags);
+    ok(!skipped, "got skipped %lu.\n", skipped);
+    for (i = 0; i < ARRAY_SIZE(string_hex_tests); ++i)
+    {
+        for (wide = 0; wide < 2; ++wide)
+        {
+            if (wide)
+            {
+                unsigned int j = 0;
+                while ((str_w[j] = string_hex_tests[i][j]))
+                    ++j;
+            }
+            winetest_push_context("test %lu, %s", i, wide ? debugstr_w(str_w)
+                    : debugstr_a(string_hex_tests[i]));
+            expected_len = 0xdeadbeef;
+            expected_skipped = 0xdeadbeef;
+            expected_flags = 0xdeadbeef;
+            expected_err = string_to_hex(wide ? (void *)str_w : (void *)string_hex_tests[i], wide, 0, NULL,
+                    &expected_len, &expected_skipped, &expected_flags);
+            bufLen = 0xdeadbeef;
+            skipped = 0xdeadbeef;
+            flags = 0xdeadbeef;
+            SetLastError(0xdeadbeef);
+            if (wide)
+                ret = CryptStringToBinaryW(str_w, 0, CRYPT_STRING_HEX, NULL, &bufLen, &skipped, &flags);
+            else
+                ret = CryptStringToBinaryA(string_hex_tests[i], 0, CRYPT_STRING_HEX, NULL, &bufLen, &skipped, &flags);
+            ok(bufLen == expected_len, "got length %lu.\n", bufLen);
+            ok(skipped == expected_skipped, "got skipped %lu.\n", skipped);
+            ok(flags == expected_flags, "got flags %lu.\n", flags);
+            if (expected_err)
+                ok(!ret && GetLastError() == expected_err, "got ret %d, error %lu.\n", ret, GetLastError());
+            else
+                ok(ret, "got error %lu.\n", GetLastError());
+            memset(expected, 0xcc, sizeof(expected));
+            expected_len = 8;
+            expected_skipped = 0xdeadbeef;
+            expected_flags = 0xdeadbeef;
+            expected_err = string_to_hex(wide ? (void *)str_w : (void *)string_hex_tests[i], wide, 0, expected,
+                    &expected_len, &expected_skipped, &expected_flags);
+            memset(buf, 0xcc, sizeof(buf));
+            bufLen = 8;
+            skipped = 0xdeadbeef;
+            flags = 0xdeadbeef;
+            SetLastError(0xdeadbeef);
+            if (wide)
+                ret = CryptStringToBinaryW(str_w, 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+            else
+                ret = CryptStringToBinaryA(string_hex_tests[i], 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+            ok(!memcmp(buf, expected, sizeof(buf)), "data does not match, buf[0] %#x, buf[1] %#x.\n", buf[0], buf[1]);
+            ok(bufLen == expected_len, "got length %lu.\n", bufLen);
+            if (expected_err)
+                ok(!ret && GetLastError() == expected_err, "got ret %d, error %lu.\n", ret, GetLastError());
+            else
+                ok(ret, "got error %lu.\n", GetLastError());
+            ok(bufLen == expected_len, "got length %lu.\n", bufLen);
+            ok(skipped == expected_skipped, "got skipped %lu.\n", skipped);
+            ok(flags == expected_flags, "got flags %lu.\n", flags);
+            winetest_pop_context();
+        }
+    }
+    bufLen = 1;
+    SetLastError(0xdeadbeef);
+    skipped = 0xdeadbeef;
+    flags = 0xdeadbeef;
+    memset(buf, 0xcc, sizeof(buf));
+    ret = CryptStringToBinaryA("0102", 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+    ok(!ret && GetLastError() == ERROR_MORE_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(!skipped, "got skipped %lu.\n", skipped);
+    ok(!flags, "got flags %lu.\n", flags);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    bufLen = 1;
+    SetLastError(0xdeadbeef);
+    skipped = 0xdeadbeef;
+    flags = 0xdeadbeef;
+    memset(buf, 0xcc, sizeof(buf));
+    ret = CryptStringToBinaryA("0102q", 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(!skipped, "got skipped %lu.\n", skipped);
+    ok(!flags, "got flags %lu.\n", flags);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    bufLen = 1;
+    SetLastError(0xdeadbeef);
+    skipped = 0xdeadbeef;
+    flags = 0xdeadbeef;
+    memset(buf, 0xcc, sizeof(buf));
+    ret = CryptStringToBinaryW(L"0102q", 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+    ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(!skipped, "got skipped %lu.\n", skipped);
+    ok(!flags, "got flags %lu.\n", flags);
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    bufLen = 1;
+    SetLastError(0xdeadbeef);
+    skipped = 0xdeadbeef;
+    flags = 0xdeadbeef;
+    memset(buf, 0xcc, sizeof(buf));
+    ret = CryptStringToBinaryW(L"0102", 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+    ok(bufLen == 1, "got length %lu.\n", bufLen);
+    ok(!ret && GetLastError() == ERROR_MORE_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+    ok(buf[0] == 1, "got buf[0] %#x.\n", buf[0]);
+    ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+    /* It looks like Windows is normalizing Unicode strings in some way which depending on locale may result in
+     * some invalid characters in 128-255 range being converted into sequences starting with valid hex numbers.
+     * Just avoiding characters in the 128-255 range in test. */
+    for (i = 1; i < 128; ++i)
+    {
+        char str_a[16];
+        for (wide = 0; wide < 2; ++wide)
+        {
+            if (wide)
+            {
+                str_w[0] = i;
+                wcscpy(str_w + 1, L"00");
+            }
+            else
+            {
+                str_a[0] = i;
+                strcpy(str_a + 1, "00");
+            }
+            winetest_push_context("char %#lx, %s", i, wide ? debugstr_w(str_w) : debugstr_a(str_a));
+            bufLen = 1;
+            buf[0] = buf[1] = 0xcc;
+            SetLastError(0xdeadbeef);
+            if (wide)
+                ret = CryptStringToBinaryW(str_w, 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+            else
+                ret = CryptStringToBinaryA(str_a, 0, CRYPT_STRING_HEX, buf, &bufLen, &skipped, &flags);
+            ok(bufLen == 1, "got length %lu.\n", bufLen);
+            if (is_hex_string_special_char(i))
+            {
+                ok(ret, "got error %lu.\n", GetLastError());
+                ok(!buf[0], "got buf[0] %#x.\n", buf[0]);
+                ok(buf[1] == 0xcc, "got buf[1] %#x.\n", buf[1]);
+            }
+            else
+            {
+                ok(!ret && GetLastError() == ERROR_INVALID_DATA, "got ret %d, error %lu.\n", ret, GetLastError());
+                if (isdigit(i) || (tolower(i) >= 'a' && tolower(i) <= 'f'))
+                {
+                    ok(buf[0] == (digit_from_char(i) << 4), "got buf[0] %#x.\n", buf[0]);
+                    ok(buf[1] == 0xcc, "got buf[0] %#x.\n", buf[1]);
+                }
+                else
+                {
+                    ok(buf[0] == 0xcc, "got buf[0] %#x.\n", buf[0]);
+                }
+            }
+            winetest_pop_context();
+        }
+    }
}

START_TEST(base64)
{
     test_CryptBinaryToString();
-    testStringToBinaryA();
+    test_CryptStringToBinary();
}
diff --git a/wine/dlls/crypt32/tests/cert.c b/wine/dlls/crypt32/tests/cert.c
index 3cdb5e5ce..882bb4a07 100644
--- a/wine/dlls/crypt32/tests/cert.c
+++ b/wine/dlls/crypt32/tests/cert.c
@@ -554,7 +554,7 @@ static void testCertProperties(void)
     ok(ret, "CertGetCertificateContextProperty failed: %08lx\n", GetLastError());
     if (ret)
     {
-        LPBYTE buf = HeapAlloc(GetProcessHeap(), 0, size);
+        LPBYTE buf = malloc(size);

          if (buf)
          {
@@ -563,7 +563,7 @@ static void testCertProperties(void)
               ok(ret, "CertGetCertificateContextProperty failed: %08lx\n",
               GetLastError());
               ok(!memcmp(buf, subjectKeyId, size), "Unexpected subject key id\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
     }
     CertFreeCertificateContext(context);
@@ -1640,7 +1640,7 @@ static void testGetIssuerCert(void)
     size = 0;
     ok(CertStrToNameW(X509_ASN_ENCODING, L"CN=dummy, T=Test", CERT_X500_NAME_STR, NULL, NULL, &size, NULL),
          "CertStrToName should have worked\n");
-    certencoded = HeapAlloc(GetProcessHeap(), 0, size);
+    certencoded = malloc(size);
     ok(CertStrToNameW(X509_ASN_ENCODING, L"CN=dummy, T=Test", CERT_X500_NAME_STR, NULL, certencoded, &size, NULL),
          "CertStrToName should have worked\n");
     certsubject.pbData = certencoded;
@@ -1663,7 +1663,7 @@ static void testGetIssuerCert(void)
     CertFreeCertificateContext(cert2);
     CertFreeCertificateContext(cert3);
     CertCloseStore(store, 0);
-    HeapFree(GetProcessHeap(), 0, certencoded);
+    free(certencoded);

     /* Test root storage self-signed certificate */
     store = CertOpenStore(CERT_STORE_PROV_SYSTEM, 0, 0, CERT_SYSTEM_STORE_CURRENT_USER, L"ROOT");
@@ -1913,7 +1913,7 @@ static void testVerifyCertSig(HCRYPTPROV csp, const CRYPT_DATA_BLOB *toBeSigned,
          }
          CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE, X509_ASN_ENCODING,
          (LPSTR)sigOID, 0, NULL, NULL, &pubKeySize);
-        pubKeyInfo = HeapAlloc(GetProcessHeap(), 0, pubKeySize);
+        pubKeyInfo = malloc(pubKeySize);
          if (pubKeyInfo)
          {
               ret = CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE,
@@ -1927,7 +1927,7 @@ static void testVerifyCertSig(HCRYPTPROV csp, const CRYPT_DATA_BLOB *toBeSigned,
               ok(ret, "CryptVerifyCertificateSignature failed: %08lx\n",
                    GetLastError());
               }
-            HeapFree(GetProcessHeap(), 0, pubKeyInfo);
+            free(pubKeyInfo);
          }
          LocalFree(cert);
     }
@@ -2000,7 +2000,7 @@ static void testVerifyCertSigEx(HCRYPTPROV csp, const CRYPT_DATA_BLOB *toBeSigne
          */
          CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE, X509_ASN_ENCODING,
          (LPSTR)sigOID, 0, NULL, NULL, &size);
-        pubKeyInfo = HeapAlloc(GetProcessHeap(), 0, size);
+        pubKeyInfo = malloc(size);
          if (pubKeyInfo)
          {
               ret = CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE,
@@ -2014,7 +2014,7 @@ static void testVerifyCertSigEx(HCRYPTPROV csp, const CRYPT_DATA_BLOB *toBeSigne
               ok(ret, "CryptVerifyCertificateSignatureEx failed: %08lx\n",
                    GetLastError());
               }
-            HeapFree(GetProcessHeap(), 0, pubKeyInfo);
+            free(pubKeyInfo);
          }
          LocalFree(cert);
     }
@@ -2114,7 +2114,7 @@ static void testSignAndEncodeCert(void)
     /* oid_rsa_md5 not present in some win2k */
     if (ret)
     {
-        LPBYTE buf = HeapAlloc(GetProcessHeap(), 0, size);
+        LPBYTE buf = malloc(size);

          if (buf)
          {
@@ -2135,7 +2135,7 @@ static void testSignAndEncodeCert(void)
               else if (size == sizeof(md5SignedEmptyCertNoNull))
               ok(!memcmp(buf, md5SignedEmptyCertNoNull, size),
                    "Unexpected value\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
     }
}
@@ -2188,7 +2188,7 @@ static void testCreateSelfSignCert(void)
               ok(ret && size, "Expected non-zero key provider info\n");
               if (size)
               {
-                PCRYPT_KEY_PROV_INFO pInfo = HeapAlloc(GetProcessHeap(), 0, size);
+                PCRYPT_KEY_PROV_INFO pInfo = malloc(size);

               if (pInfo)
               {
@@ -2206,7 +2206,7 @@ static void testCreateSelfSignCert(void)
                         ok(pInfo->dwKeySpec == AT_SIGNATURE,
                         "Expected AT_SIGNATURE, got %ld\n", pInfo->dwKeySpec);
                    }
-                    HeapFree(GetProcessHeap(), 0, pInfo);
+                    free(pInfo);
               }
               }

@@ -2262,7 +2262,7 @@ static void testCreateSelfSignCert(void)
          ok(ret && size, "Expected non-zero key provider info\n");
          if (size)
          {
-            PCRYPT_KEY_PROV_INFO pInfo = HeapAlloc(GetProcessHeap(), 0, size);
+            PCRYPT_KEY_PROV_INFO pInfo = malloc(size);

               if (pInfo)
               {
@@ -2280,7 +2280,7 @@ static void testCreateSelfSignCert(void)
                    ok(pInfo->dwKeySpec == AT_SIGNATURE,
                         "Expected AT_SIGNATURE, got %ld\n", pInfo->dwKeySpec);
               }
-                HeapFree(GetProcessHeap(), 0, pInfo);
+                free(pInfo);
               }
          }

@@ -2309,7 +2309,7 @@ static void testCreateSelfSignCert(void)
          ok(ret && size, "Expected non-zero key provider info\n");
          if (size)
          {
-            PCRYPT_KEY_PROV_INFO pInfo = HeapAlloc(GetProcessHeap(), 0, size);
+            PCRYPT_KEY_PROV_INFO pInfo = malloc(size);

               if (pInfo)
               {
@@ -2327,7 +2327,7 @@ static void testCreateSelfSignCert(void)
                    ok(pInfo->dwKeySpec == AT_KEYEXCHANGE,
                         "Expected AT_KEYEXCHANGE, got %ld\n", pInfo->dwKeySpec);
               }
-                HeapFree(GetProcessHeap(), 0, pInfo);
+                free(pInfo);
               }
          }

@@ -2386,7 +2386,7 @@ static void testCreateSelfSignCert(void)
          ok(ret && size, "Expected non-zero key provider info\n");
          if (size)
          {
-            PCRYPT_KEY_PROV_INFO pInfo = HeapAlloc(GetProcessHeap(), 0, size);
+            PCRYPT_KEY_PROV_INFO pInfo = malloc(size);

               if (pInfo)
               {
@@ -2404,7 +2404,7 @@ static void testCreateSelfSignCert(void)
                    ok(pInfo->dwKeySpec == AT_KEYEXCHANGE,
                         "Expected AT_KEYEXCHANGE, got %ld\n", pInfo->dwKeySpec);
               }
-                HeapFree(GetProcessHeap(), 0, pInfo);
+                free(pInfo);
               }
          }

@@ -2627,7 +2627,7 @@ static void testKeyUsage(void)
          ret = CertGetEnhancedKeyUsage(context,
          CERT_FIND_EXT_ONLY_ENHKEY_USAGE_FLAG, NULL, &bufSize);
          ok(ret, "CertGetEnhancedKeyUsage failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufSize);
+        buf = malloc(bufSize);
          if (buf)
          {
               PCERT_ENHKEY_USAGE pUsage = (PCERT_ENHKEY_USAGE)buf;
@@ -2644,11 +2644,11 @@ static void testKeyUsage(void)
               ok(!strcmp(pUsage->rgpszUsageIdentifier[i], keyUsages[i]),
                    "Expected %s, got %s\n", keyUsages[i],
                    pUsage->rgpszUsageIdentifier[i]);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          ret = CertGetEnhancedKeyUsage(context, 0, NULL, &bufSize);
          ok(ret, "CertGetEnhancedKeyUsage failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufSize);
+        buf = malloc(bufSize);
          if (buf)
          {
               PCERT_ENHKEY_USAGE pUsage = (PCERT_ENHKEY_USAGE)buf;
@@ -2668,7 +2668,7 @@ static void testKeyUsage(void)
               ok(!strcmp(pUsage->rgpszUsageIdentifier[i], keyUsages[i]),
                    "Expected %s, got %s\n", keyUsages[i],
                    pUsage->rgpszUsageIdentifier[i]);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          /* Shouldn't find it as an extended property */
          ret = CertGetEnhancedKeyUsage(context,
@@ -2681,7 +2681,7 @@ static void testKeyUsage(void)
          GetLastError());
          ret = CertGetEnhancedKeyUsage(context, 0, NULL, &bufSize);
          ok(ret, "CertGetEnhancedKeyUsage failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufSize);
+        buf = malloc(bufSize);
          if (buf)
          {
               PCERT_ENHKEY_USAGE pUsage = (PCERT_ENHKEY_USAGE)buf;
@@ -2696,13 +2696,13 @@ static void testKeyUsage(void)
               ok(!strcmp(pUsage->rgpszUsageIdentifier[0], szOID_RSA_RSA),
               "Expected %s, got %s\n", szOID_RSA_RSA,
               pUsage->rgpszUsageIdentifier[0]);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          /* But querying the cert directly returns its usage */
          ret = CertGetEnhancedKeyUsage(context,
          CERT_FIND_EXT_ONLY_ENHKEY_USAGE_FLAG, NULL, &bufSize);
          ok(ret, "CertGetEnhancedKeyUsage failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufSize);
+        buf = malloc(bufSize);
          if (buf)
          {
               PCERT_ENHKEY_USAGE pUsage = (PCERT_ENHKEY_USAGE)buf;
@@ -2718,7 +2718,7 @@ static void testKeyUsage(void)
               ok(!strcmp(pUsage->rgpszUsageIdentifier[i], keyUsages[i]),
                    "Expected %s, got %s\n", keyUsages[i],
                    pUsage->rgpszUsageIdentifier[i]);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          /* And removing the only usage identifier in the extended property
          * results in the cert's key usage being found.
@@ -2727,7 +2727,7 @@ static void testKeyUsage(void)
          ok(ret, "CertRemoveEnhancedKeyUsage failed: %08lx\n", GetLastError());
          ret = CertGetEnhancedKeyUsage(context, 0, NULL, &bufSize);
          ok(ret, "CertGetEnhancedKeyUsage failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, bufSize);
+        buf = malloc(bufSize);
          if (buf)
          {
               PCERT_ENHKEY_USAGE pUsage = (PCERT_ENHKEY_USAGE)buf;
@@ -2743,7 +2743,7 @@ static void testKeyUsage(void)
               ok(!strcmp(pUsage->rgpszUsageIdentifier[i], keyUsages[i]),
                    "Expected %s, got %s\n", keyUsages[i],
                    pUsage->rgpszUsageIdentifier[i]);
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }

          CertFreeCertificateContext(context);
@@ -2810,7 +2810,7 @@ static void testGetValidUsages(void)
     ok(ret, "CertGetValidUsages failed: %08lx\n", GetLastError());
     ok(numOIDs == 3, "Expected 3, got %d\n", numOIDs);
     ok(size, "Expected non-zero size\n");
-    oids = HeapAlloc(GetProcessHeap(), 0, size);
+    oids = malloc(size);
     if (oids)
     {
          int i;
@@ -2825,7 +2825,7 @@ static void testGetValidUsages(void)
          for (i = 0; i < numOIDs; i++)
               ok(!lstrcmpA(oids[i], expectedOIDs[i]), "unexpected OID %s\n",
               oids[i]);
-        HeapFree(GetProcessHeap(), 0, oids);
+        free(oids);
     }
     numOIDs = 0xdeadbeef;
     /* Oddly enough, this crashes when the number of contexts is not 1:
@@ -2837,7 +2837,7 @@ static void testGetValidUsages(void)
     ok(ret, "CertGetValidUsages failed: %08lx\n", GetLastError());
     ok(numOIDs == 3, "Expected 3, got %d\n", numOIDs);
     ok(size, "Expected non-zero size\n");
-    oids = HeapAlloc(GetProcessHeap(), 0, size);
+    oids = malloc(size);
     if (oids)
     {
          int i;
@@ -2847,7 +2847,7 @@ static void testGetValidUsages(void)
          for (i = 0; i < numOIDs; i++)
               ok(!lstrcmpA(oids[i], expectedOIDs[i]), "unexpected OID %s\n",
               oids[i]);
-        HeapFree(GetProcessHeap(), 0, oids);
+        free(oids);
     }
     numOIDs = 0xdeadbeef;
     size = 0;
@@ -2855,7 +2855,7 @@ static void testGetValidUsages(void)
     ok(ret, "CertGetValidUsages failed: %08lx\n", GetLastError());
     ok(numOIDs == 2, "Expected 2, got %d\n", numOIDs);
     ok(size, "Expected non-zero size\n");
-    oids = HeapAlloc(GetProcessHeap(), 0, size);
+    oids = malloc(size);
     if (oids)
     {
          int i;
@@ -2865,7 +2865,7 @@ static void testGetValidUsages(void)
          for (i = 0; i < numOIDs; i++)
               ok(!lstrcmpA(oids[i], expectedOIDs2[i]), "unexpected OID %s\n",
               oids[i]);
-        HeapFree(GetProcessHeap(), 0, oids);
+        free(oids);
     }
     numOIDs = 0xdeadbeef;
     size = 0;
@@ -2873,7 +2873,7 @@ static void testGetValidUsages(void)
     ok(ret, "CertGetValidUsages failed: %08lx\n", GetLastError());
     ok(numOIDs == 2, "Expected 2, got %d\n", numOIDs);
     ok(size, "Expected non-zero size\n");
-    oids = HeapAlloc(GetProcessHeap(), 0, size);
+    oids = malloc(size);
     if (oids)
     {
          int i;
@@ -2883,7 +2883,7 @@ static void testGetValidUsages(void)
          for (i = 0; i < numOIDs; i++)
               ok(!lstrcmpA(oids[i], expectedOIDs2[i]), "unexpected OID %s\n",
               oids[i]);
-        HeapFree(GetProcessHeap(), 0, oids);
+        free(oids);
     }
     CertFreeCertificateContext(contexts[0]);
     CertFreeCertificateContext(contexts[1]);
@@ -3537,6 +3537,520 @@ static const BYTE rootSignedCRL[] = {
0xd5,0xbc,0xb0,0xd5,0xa5,0x9c,0x1b,0x72,0xc3,0x0f,0xa3,0xe3,0x3c,0xf0,0xc3,
0x91,0xe8,0x93,0x4f,0xd4,0x2f };

+static const BYTE ocsp_cert[] = {
+  0x30, 0x82, 0x06, 0xcd, 0x30, 0x82, 0x05, 0xb5, 0xa0, 0x03, 0x02, 0x01,
+  0x02, 0x02, 0x10, 0x08, 0x49, 0x8f, 0x6d, 0xd9, 0xef, 0xfb, 0x40, 0x55,
+  0x1e, 0xac, 0x54, 0x54, 0x87, 0xc1, 0xb1, 0x30, 0x0d, 0x06, 0x09, 0x2a,
+  0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x30, 0x4f,
+  0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55,
+  0x53, 0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c,
+  0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63,
+  0x31, 0x29, 0x30, 0x27, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x20, 0x44,
+  0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x54, 0x4c, 0x53, 0x20,
+  0x52, 0x53, 0x41, 0x20, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x20, 0x32,
+  0x30, 0x32, 0x30, 0x20, 0x43, 0x41, 0x31, 0x30, 0x1e, 0x17, 0x0d, 0x32,
+  0x31, 0x30, 0x34, 0x32, 0x38, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x5a,
+  0x17, 0x0d, 0x32, 0x32, 0x30, 0x35, 0x32, 0x39, 0x32, 0x33, 0x35, 0x39,
+  0x35, 0x39, 0x5a, 0x30, 0x6b, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55,
+  0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x13, 0x30, 0x11, 0x06, 0x03,
+  0x55, 0x04, 0x08, 0x13, 0x0a, 0x57, 0x61, 0x73, 0x68, 0x69, 0x6e, 0x67,
+  0x74, 0x6f, 0x6e, 0x31, 0x11, 0x30, 0x0f, 0x06, 0x03, 0x55, 0x04, 0x07,
+  0x13, 0x08, 0x42, 0x65, 0x6c, 0x6c, 0x65, 0x76, 0x75, 0x65, 0x31, 0x14,
+  0x30, 0x12, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0b, 0x56, 0x61, 0x6c,
+  0x76, 0x65, 0x20, 0x43, 0x6f, 0x72, 0x70, 0x2e, 0x31, 0x1e, 0x30, 0x1c,
+  0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x15, 0x2a, 0x2e, 0x63, 0x6d, 0x2e,
+  0x73, 0x74, 0x65, 0x61, 0x6d, 0x70, 0x6f, 0x77, 0x65, 0x72, 0x65, 0x64,
+  0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
+  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
+  0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01,
+  0x00, 0xcd, 0x98, 0x0c, 0x13, 0xb2, 0xb9, 0xf2, 0xa5, 0xc6, 0x52, 0xad,
+  0xf9, 0x4d, 0xcf, 0x1e, 0x2b, 0x74, 0x05, 0xd1, 0x2e, 0x95, 0xc3, 0x9d,
+  0x9b, 0x03, 0x2a, 0xc6, 0x65, 0x1e, 0xda, 0x5d, 0x57, 0x3c, 0x61, 0xa1,
+  0x3d, 0xa3, 0xe7, 0x0c, 0xdd, 0xb1, 0x6b, 0x30, 0x97, 0x99, 0xc7, 0x77,
+  0xab, 0xc2, 0xb0, 0x0a, 0x5b, 0x1c, 0x86, 0x55, 0x42, 0x25, 0xa8, 0x4e,
+  0xe2, 0x61, 0xfe, 0x88, 0x10, 0x25, 0xf5, 0x8e, 0x9c, 0x0f, 0xc7, 0xa5,
+  0xef, 0x9d, 0xd5, 0xf0, 0x2a, 0xf2, 0x31, 0x59, 0x59, 0xfc, 0xe0, 0x1f,
+  0x8f, 0xb4, 0xa1, 0x06, 0x32, 0x04, 0x37, 0x3d, 0x9d, 0xad, 0xc1, 0xe0,
+  0x00, 0x3d, 0x8d, 0x60, 0x4c, 0x9e, 0x6a, 0x1f, 0xd2, 0xf6, 0xf8, 0x86,
+  0x0b, 0x11, 0x7b, 0xfd, 0x75, 0xae, 0x20, 0x9b, 0xca, 0x52, 0x5f, 0x4e,
+  0xad, 0x2e, 0xa2, 0xce, 0xed, 0x35, 0x08, 0x23, 0xa8, 0x6e, 0x61, 0x7e,
+  0x18, 0x1a, 0x6a, 0xd9, 0xe0, 0x3b, 0x52, 0x64, 0xe9, 0x2c, 0x81, 0x8f,
+  0xbc, 0x4b, 0x48, 0xd1, 0x7a, 0x3e, 0x02, 0x9c, 0xad, 0x87, 0x73, 0xae,
+  0xaa, 0xea, 0x32, 0xfb, 0x07, 0x4e, 0xcb, 0xe9, 0xac, 0xac, 0x50, 0x0f,
+  0x49, 0xb7, 0x23, 0x3b, 0x1f, 0xb2, 0x24, 0x46, 0x78, 0x32, 0x11, 0x9e,
+  0xa2, 0xeb, 0xd8, 0x8b, 0x7e, 0x56, 0x92, 0xaa, 0x29, 0xbd, 0x55, 0xc8,
+  0x3e, 0x69, 0xe2, 0x56, 0xf4, 0x24, 0x58, 0x7b, 0xf8, 0xb0, 0xbb, 0x72,
+  0xb7, 0x38, 0x34, 0xe3, 0x0f, 0x30, 0xf4, 0xfd, 0x44, 0xf1, 0x53, 0x0f,
+  0xc5, 0x31, 0xd6, 0xad, 0x45, 0xbf, 0x57, 0x2c, 0x4c, 0xe5, 0x1a, 0xc0,
+  0x08, 0x25, 0x88, 0x2f, 0xca, 0x07, 0x2e, 0x35, 0x31, 0xa7, 0x40, 0x3a,
+  0x71, 0x1d, 0xba, 0x09, 0xf8, 0x76, 0x6c, 0x69, 0xb2, 0x89, 0xd7, 0xbe,
+  0xca, 0x9d, 0xf5, 0xd4, 0x7d, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x82,
+  0x03, 0x87, 0x30, 0x82, 0x03, 0x83, 0x30, 0x1f, 0x06, 0x03, 0x55, 0x1d,
+  0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14, 0xb7, 0x6b, 0xa2, 0xea, 0xa8,
+  0xaa, 0x84, 0x8c, 0x79, 0xea, 0xb4, 0xda, 0x0f, 0x98, 0xb2, 0xc5, 0x95,
+  0x76, 0xb9, 0xf4, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x0e, 0x04, 0x16,
+  0x04, 0x14, 0x22, 0x68, 0x57, 0xb9, 0xc0, 0x1f, 0xce, 0xa6, 0xbf, 0xb6,
+  0x55, 0xcb, 0x2a, 0x1b, 0xe6, 0xe0, 0x76, 0x94, 0x07, 0x06, 0x30, 0x35,
+  0x06, 0x03, 0x55, 0x1d, 0x11, 0x04, 0x2e, 0x30, 0x2c, 0x82, 0x15, 0x2a,
+  0x2e, 0x63, 0x6d, 0x2e, 0x73, 0x74, 0x65, 0x61, 0x6d, 0x70, 0x6f, 0x77,
+  0x65, 0x72, 0x65, 0x64, 0x2e, 0x63, 0x6f, 0x6d, 0x82, 0x13, 0x63, 0x6d,
+  0x2e, 0x73, 0x74, 0x65, 0x61, 0x6d, 0x70, 0x6f, 0x77, 0x65, 0x72, 0x65,
+  0x64, 0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f,
+  0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x05, 0xa0, 0x30, 0x1d, 0x06,
+  0x03, 0x55, 0x1d, 0x25, 0x04, 0x16, 0x30, 0x14, 0x06, 0x08, 0x2b, 0x06,
+  0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05,
+  0x05, 0x07, 0x03, 0x02, 0x30, 0x81, 0x8b, 0x06, 0x03, 0x55, 0x1d, 0x1f,
+  0x04, 0x81, 0x83, 0x30, 0x81, 0x80, 0x30, 0x3e, 0xa0, 0x3c, 0xa0, 0x3a,
+  0x86, 0x38, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x72, 0x6c,
+  0x33, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63,
+  0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x54,
+  0x4c, 0x53, 0x52, 0x53, 0x41, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x32,
+  0x30, 0x32, 0x30, 0x43, 0x41, 0x31, 0x2e, 0x63, 0x72, 0x6c, 0x30, 0x3e,
+  0xa0, 0x3c, 0xa0, 0x3a, 0x86, 0x38, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f,
+  0x2f, 0x63, 0x72, 0x6c, 0x34, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65,
+  0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43,
+  0x65, 0x72, 0x74, 0x54, 0x4c, 0x53, 0x52, 0x53, 0x41, 0x53, 0x48, 0x41,
+  0x32, 0x35, 0x36, 0x32, 0x30, 0x32, 0x30, 0x43, 0x41, 0x31, 0x2e, 0x63,
+  0x72, 0x6c, 0x30, 0x3e, 0x06, 0x03, 0x55, 0x1d, 0x20, 0x04, 0x37, 0x30,
+  0x35, 0x30, 0x33, 0x06, 0x06, 0x67, 0x81, 0x0c, 0x01, 0x02, 0x02, 0x30,
+  0x29, 0x30, 0x27, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x02,
+  0x01, 0x16, 0x1b, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77,
+  0x77, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63,
+  0x6f, 0x6d, 0x2f, 0x43, 0x50, 0x53, 0x30, 0x7d, 0x06, 0x08, 0x2b, 0x06,
+  0x01, 0x05, 0x05, 0x07, 0x01, 0x01, 0x04, 0x71, 0x30, 0x6f, 0x30, 0x24,
+  0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x01, 0x86, 0x18,
+  0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x6f, 0x63, 0x73, 0x70, 0x2e,
+  0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d,
+  0x30, 0x47, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x02,
+  0x86, 0x3b, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x61, 0x63,
+  0x65, 0x72, 0x74, 0x73, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72,
+  0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65,
+  0x72, 0x74, 0x54, 0x4c, 0x53, 0x52, 0x53, 0x41, 0x53, 0x48, 0x41, 0x32,
+  0x35, 0x36, 0x32, 0x30, 0x32, 0x30, 0x43, 0x41, 0x31, 0x2e, 0x63, 0x72,
+  0x74, 0x30, 0x0c, 0x06, 0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04,
+  0x02, 0x30, 0x00, 0x30, 0x82, 0x01, 0x7e, 0x06, 0x0a, 0x2b, 0x06, 0x01,
+  0x04, 0x01, 0xd6, 0x79, 0x02, 0x04, 0x02, 0x04, 0x82, 0x01, 0x6e, 0x04,
+  0x82, 0x01, 0x6a, 0x01, 0x68, 0x00, 0x76, 0x00, 0x29, 0x79, 0xbe, 0xf0,
+  0x9e, 0x39, 0x39, 0x21, 0xf0, 0x56, 0x73, 0x9f, 0x63, 0xa5, 0x77, 0xe5,
+  0xbe, 0x57, 0x7d, 0x9c, 0x60, 0x0a, 0xf8, 0xf9, 0x4d, 0x5d, 0x26, 0x5c,
+  0x25, 0x5d, 0xc7, 0x84, 0x00, 0x00, 0x01, 0x79, 0x19, 0x43, 0x10, 0x65,
+  0x00, 0x00, 0x04, 0x03, 0x00, 0x47, 0x30, 0x45, 0x02, 0x21, 0x00, 0x93,
+  0x5f, 0x66, 0xe4, 0xfe, 0x76, 0x25, 0xe6, 0x07, 0x74, 0xa1, 0x8b, 0x7f,
+  0x37, 0xad, 0xb1, 0x40, 0x8f, 0x20, 0x66, 0x71, 0x57, 0x14, 0x2c, 0x2e,
+  0x28, 0xe0, 0xb2, 0x95, 0xd5, 0x19, 0xd0, 0x02, 0x20, 0x32, 0xd1, 0xa8,
+  0x59, 0xfd, 0x69, 0x24, 0x8a, 0x27, 0x7e, 0x56, 0x06, 0xce, 0x6d, 0xeb,
+  0xa1, 0xc6, 0x2a, 0xce, 0x4b, 0x37, 0xb1, 0x25, 0xca, 0x6d, 0xd3, 0x43,
+  0xf3, 0xdb, 0xb8, 0xa5, 0x5e, 0x00, 0x76, 0x00, 0x22, 0x45, 0x45, 0x07,
+  0x59, 0x55, 0x24, 0x56, 0x96, 0x3f, 0xa1, 0x2f, 0xf1, 0xf7, 0x6d, 0x86,
+  0xe0, 0x23, 0x26, 0x63, 0xad, 0xc0, 0x4b, 0x7f, 0x5d, 0xc6, 0x83, 0x5c,
+  0x6e, 0xe2, 0x0f, 0x02, 0x00, 0x00, 0x01, 0x79, 0x19, 0x43, 0x10, 0xa4,
+  0x00, 0x00, 0x04, 0x03, 0x00, 0x47, 0x30, 0x45, 0x02, 0x20, 0x3a, 0x73,
+  0x53, 0xfb, 0xbb, 0x42, 0xdf, 0x2e, 0xa2, 0xc0, 0xc5, 0x29, 0x57, 0xda,
+  0xb9, 0x0b, 0x76, 0x58, 0xb6, 0xeb, 0xd3, 0x4d, 0x10, 0x95, 0x1b, 0x58,
+  0x3e, 0x58, 0x86, 0xea, 0xec, 0xe5, 0x02, 0x21, 0x00, 0xeb, 0xb2, 0xfe,
+  0x83, 0x74, 0xdf, 0xb5, 0xfd, 0x8f, 0x74, 0x82, 0xd3, 0x8f, 0x6b, 0xce,
+  0x63, 0x8b, 0x93, 0x94, 0x08, 0x7b, 0x1c, 0x6b, 0x48, 0xae, 0x59, 0xa1,
+  0x7e, 0xec, 0x59, 0xdf, 0x56, 0x00, 0x76, 0x00, 0x51, 0xa3, 0xb0, 0xf5,
+  0xfd, 0x01, 0x79, 0x9c, 0x56, 0x6d, 0xb8, 0x37, 0x78, 0x8f, 0x0c, 0xa4,
+  0x7a, 0xcc, 0x1b, 0x27, 0xcb, 0xf7, 0x9e, 0x88, 0x42, 0x9a, 0x0d, 0xfe,
+  0xd4, 0x8b, 0x05, 0xe5, 0x00, 0x00, 0x01, 0x79, 0x19, 0x43, 0x10, 0xea,
+  0x00, 0x00, 0x04, 0x03, 0x00, 0x47, 0x30, 0x45, 0x02, 0x20, 0x68, 0x89,
+  0x8b, 0xab, 0x98, 0xd3, 0x4f, 0x41, 0x4f, 0x7d, 0x1c, 0x52, 0xbe, 0x1b,
+  0xf1, 0xbe, 0xb3, 0x68, 0x49, 0x5a, 0x91, 0x93, 0xdc, 0xac, 0xba, 0x6e,
+  0x58, 0x8d, 0xcd, 0x3c, 0x5a, 0x26, 0x02, 0x21, 0x00, 0x85, 0x09, 0xf7,
+  0x21, 0x4a, 0x66, 0x45, 0x77, 0xfe, 0xd5, 0x77, 0x25, 0xd5, 0xc5, 0x1a,
+  0xb3, 0x33, 0xd8, 0x86, 0x52, 0xcc, 0xe1, 0x26, 0x21, 0x03, 0xcf, 0x1b,
+  0x34, 0x24, 0xab, 0xc0, 0x1f, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48,
+  0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x03, 0x82, 0x01, 0x01,
+  0x00, 0xbd, 0x22, 0x40, 0xf1, 0x6d, 0xe7, 0x68, 0x89, 0x82, 0x53, 0xcd,
+  0x64, 0xed, 0x21, 0x17, 0x90, 0x3a, 0xd0, 0xa3, 0x21, 0x42, 0x40, 0x60,
+  0xf2, 0x2c, 0xf7, 0x40, 0xef, 0xc3, 0xf0, 0x22, 0x24, 0xc2, 0x51, 0x17,
+  0x9d, 0x4b, 0x10, 0x9f, 0x86, 0x1a, 0x05, 0x4c, 0x6a, 0xe0, 0x13, 0xbb,
+  0x29, 0xad, 0xf7, 0x18, 0x5f, 0x76, 0x01, 0x10, 0x8b, 0x1c, 0x29, 0x79,
+  0x23, 0x94, 0x58, 0x1a, 0xa6, 0xf8, 0xac, 0x9b, 0x2e, 0xe0, 0x70, 0x1d,
+  0x06, 0x1a, 0xe9, 0x5d, 0x24, 0x9f, 0x03, 0xff, 0x40, 0xe5, 0xc1, 0xb0,
+  0xb9, 0xa7, 0x7e, 0x19, 0x3d, 0x0c, 0x99, 0x89, 0x81, 0xe4, 0x53, 0x9b,
+  0xbd, 0x66, 0x1b, 0xba, 0x2e, 0xcd, 0xff, 0x24, 0x16, 0xd2, 0x89, 0xc9,
+  0x75, 0xdd, 0xc9, 0x78, 0x25, 0x1e, 0x11, 0x43, 0x25, 0x06, 0x15, 0xe5,
+  0xe3, 0x6b, 0xf9, 0x33, 0xee, 0x06, 0x16, 0x92, 0x8e, 0xe1, 0x8a, 0x93,
+  0x41, 0x15, 0x8b, 0xf1, 0x06, 0xf7, 0x52, 0x07, 0x25, 0xb8, 0x6a, 0xae,
+  0x46, 0x70, 0xa6, 0x81, 0x74, 0x70, 0x3c, 0x50, 0x42, 0x85, 0x65, 0x41,
+  0xdb, 0x25, 0xb3, 0x4f, 0xce, 0x25, 0xb5, 0x2b, 0x62, 0xb7, 0x2b, 0xbf,
+  0x66, 0xc4, 0xb4, 0x8a, 0x10, 0xb0, 0x50, 0x8e, 0x84, 0xf8, 0xe5, 0x28,
+  0x86, 0xda, 0x7d, 0xe6, 0x65, 0xbf, 0xb1, 0xd5, 0x7d, 0x09, 0x28, 0x61,
+  0xa3, 0x14, 0x89, 0x23, 0x35, 0x6e, 0x9c, 0x70, 0x06, 0x8b, 0xcb, 0x84,
+  0xe8, 0x70, 0x8d, 0xb9, 0xfb, 0x74, 0xcf, 0x77, 0x63, 0x00, 0x5d, 0x8c,
+  0xbb, 0x62, 0x4a, 0x2b, 0xc2, 0x8b, 0x2c, 0xd9, 0x9a, 0xa8, 0x83, 0x6f,
+  0x06, 0x2a, 0x2a, 0x30, 0x4c, 0x39, 0xb4, 0xf8, 0x7d, 0x8c, 0x5e, 0xa7,
+  0xcb, 0xce, 0x64, 0xe0, 0x27, 0xfa, 0x24, 0x42, 0xdd, 0xd1, 0x1d, 0xf8,
+  0xa9, 0xd7, 0xc4, 0x0c, 0x92
+};
+static const BYTE ocsp_cert_issuer[] = {
+  0x30, 0x82, 0x04, 0xbe, 0x30, 0x82, 0x03, 0xa6, 0xa0, 0x03, 0x02, 0x01,
+  0x02, 0x02, 0x10, 0x06, 0xd8, 0xd9, 0x04, 0xd5, 0x58, 0x43, 0x46, 0xf6,
+  0x8a, 0x2f, 0xa7, 0x54, 0x22, 0x7e, 0xc4, 0x30, 0x0d, 0x06, 0x09, 0x2a,
+  0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x30, 0x61,
+  0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55,
+  0x53, 0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c,
+  0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63,
+  0x31, 0x19, 0x30, 0x17, 0x06, 0x03, 0x55, 0x04, 0x0b, 0x13, 0x10, 0x77,
+  0x77, 0x77, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e,
+  0x63, 0x6f, 0x6d, 0x31, 0x20, 0x30, 0x1e, 0x06, 0x03, 0x55, 0x04, 0x03,
+  0x13, 0x17, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x47,
+  0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x20, 0x52, 0x6f, 0x6f, 0x74, 0x20, 0x43,
+  0x41, 0x30, 0x1e, 0x17, 0x0d, 0x32, 0x31, 0x30, 0x34, 0x31, 0x34, 0x30,
+  0x30, 0x30, 0x30, 0x30, 0x30, 0x5a, 0x17, 0x0d, 0x33, 0x31, 0x30, 0x34,
+  0x31, 0x33, 0x32, 0x33, 0x35, 0x39, 0x35, 0x39, 0x5a, 0x30, 0x4f, 0x31,
+  0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53,
+  0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c, 0x44,
+  0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63, 0x31,
+  0x29, 0x30, 0x27, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x20, 0x44, 0x69,
+  0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x54, 0x4c, 0x53, 0x20, 0x52,
+  0x53, 0x41, 0x20, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x20, 0x32, 0x30,
+  0x32, 0x30, 0x20, 0x43, 0x41, 0x31, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d,
+  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
+  0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a, 0x02, 0x82,
+  0x01, 0x01, 0x00, 0xc1, 0x4b, 0xb3, 0x65, 0x47, 0x70, 0xbc, 0xdd, 0x4f,
+  0x58, 0xdb, 0xec, 0x9c, 0xed, 0xc3, 0x66, 0xe5, 0x1f, 0x31, 0x13, 0x54,
+  0xad, 0x4a, 0x66, 0x46, 0x1f, 0x2c, 0x0a, 0xec, 0x64, 0x07, 0xe5, 0x2e,
+  0xdc, 0xdc, 0xb9, 0x0a, 0x20, 0xed, 0xdf, 0xe3, 0xc4, 0xd0, 0x9e, 0x9a,
+  0xa9, 0x7a, 0x1d, 0x82, 0x88, 0xe5, 0x11, 0x56, 0xdb, 0x1e, 0x9f, 0x58,
+  0xc2, 0x51, 0xe7, 0x2c, 0x34, 0x0d, 0x2e, 0xd2, 0x92, 0xe1, 0x56, 0xcb,
+  0xf1, 0x79, 0x5f, 0xb3, 0xbb, 0x87, 0xca, 0x25, 0x03, 0x7b, 0x9a, 0x52,
+  0x41, 0x66, 0x10, 0x60, 0x4f, 0x57, 0x13, 0x49, 0xf0, 0xe8, 0x37, 0x67,
+  0x83, 0xdf, 0xe7, 0xd3, 0x4b, 0x67, 0x4c, 0x22, 0x51, 0xa6, 0xdf, 0x0e,
+  0x99, 0x10, 0xed, 0x57, 0x51, 0x74, 0x26, 0xe2, 0x7d, 0xc7, 0xca, 0x62,
+  0x2e, 0x13, 0x1b, 0x7f, 0x23, 0x88, 0x25, 0x53, 0x6f, 0xc1, 0x34, 0x58,
+  0x00, 0x8b, 0x84, 0xff, 0xf8, 0xbe, 0xa7, 0x58, 0x49, 0x22, 0x7b, 0x96,
+  0xad, 0xa2, 0x88, 0x9b, 0x15, 0xbc, 0xa0, 0x7c, 0xdf, 0xe9, 0x51, 0xa8,
+  0xd5, 0xb0, 0xed, 0x37, 0xe2, 0x36, 0xb4, 0x82, 0x4b, 0x62, 0xb5, 0x49,
+  0x9a, 0xec, 0xc7, 0x67, 0xd6, 0xe3, 0x3e, 0xf5, 0xe3, 0xd6, 0x12, 0x5e,
+  0x44, 0xf1, 0xbf, 0x71, 0x42, 0x7d, 0x58, 0x84, 0x03, 0x80, 0xb1, 0x81,
+  0x01, 0xfa, 0xf9, 0xca, 0x32, 0xbb, 0xb4, 0x8e, 0x27, 0x87, 0x27, 0xc5,
+  0x2b, 0x74, 0xd4, 0xa8, 0xd6, 0x97, 0xde, 0xc3, 0x64, 0xf9, 0xca, 0xce,
+  0x53, 0xa2, 0x56, 0xbc, 0x78, 0x17, 0x8e, 0x49, 0x03, 0x29, 0xae, 0xfb,
+  0x49, 0x4f, 0xa4, 0x15, 0xb9, 0xce, 0xf2, 0x5c, 0x19, 0x57, 0x6d, 0x6b,
+  0x79, 0xa7, 0x2b, 0xa2, 0x27, 0x20, 0x13, 0xb5, 0xd0, 0x3d, 0x40, 0xd3,
+  0x21, 0x30, 0x07, 0x93, 0xea, 0x99, 0xf5, 0x02, 0x03, 0x01, 0x00, 0x01,
+  0xa3, 0x82, 0x01, 0x82, 0x30, 0x82, 0x01, 0x7e, 0x30, 0x12, 0x06, 0x03,
+  0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x08, 0x30, 0x06, 0x01, 0x01,
+  0xff, 0x02, 0x01, 0x00, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x0e, 0x04,
+  0x16, 0x04, 0x14, 0xb7, 0x6b, 0xa2, 0xea, 0xa8, 0xaa, 0x84, 0x8c, 0x79,
+  0xea, 0xb4, 0xda, 0x0f, 0x98, 0xb2, 0xc5, 0x95, 0x76, 0xb9, 0xf4, 0x30,
+  0x1f, 0x06, 0x03, 0x55, 0x1d, 0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14,
+  0x03, 0xde, 0x50, 0x35, 0x56, 0xd1, 0x4c, 0xbb, 0x66, 0xf0, 0xa3, 0xe2,
+  0x1b, 0x1b, 0xc3, 0x97, 0xb2, 0x3d, 0xd1, 0x55, 0x30, 0x0e, 0x06, 0x03,
+  0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x01, 0x86,
+  0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x25, 0x04, 0x16, 0x30, 0x14, 0x06,
+  0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x06, 0x08, 0x2b,
+  0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02, 0x30, 0x76, 0x06, 0x08, 0x2b,
+  0x06, 0x01, 0x05, 0x05, 0x07, 0x01, 0x01, 0x04, 0x6a, 0x30, 0x68, 0x30,
+  0x24, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x01, 0x86,
+  0x18, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x6f, 0x63, 0x73, 0x70,
+  0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f,
+  0x6d, 0x30, 0x40, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30,
+  0x02, 0x86, 0x34, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x61,
+  0x63, 0x65, 0x72, 0x74, 0x73, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65,
+  0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43,
+  0x65, 0x72, 0x74, 0x47, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x52, 0x6f, 0x6f,
+  0x74, 0x43, 0x41, 0x2e, 0x63, 0x72, 0x74, 0x30, 0x42, 0x06, 0x03, 0x55,
+  0x1d, 0x1f, 0x04, 0x3b, 0x30, 0x39, 0x30, 0x37, 0xa0, 0x35, 0xa0, 0x33,
+  0x86, 0x31, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x72, 0x6c,
+  0x33, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63,
+  0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x47,
+  0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x52, 0x6f, 0x6f, 0x74, 0x43, 0x41, 0x2e,
+  0x63, 0x72, 0x6c, 0x30, 0x3d, 0x06, 0x03, 0x55, 0x1d, 0x20, 0x04, 0x36,
+  0x30, 0x34, 0x30, 0x0b, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x86, 0xfd,
+  0x6c, 0x02, 0x01, 0x30, 0x07, 0x06, 0x05, 0x67, 0x81, 0x0c, 0x01, 0x01,
+  0x30, 0x08, 0x06, 0x06, 0x67, 0x81, 0x0c, 0x01, 0x02, 0x01, 0x30, 0x08,
+  0x06, 0x06, 0x67, 0x81, 0x0c, 0x01, 0x02, 0x02, 0x30, 0x08, 0x06, 0x06,
+  0x67, 0x81, 0x0c, 0x01, 0x02, 0x03, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86,
+  0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x03, 0x82, 0x01,
+  0x01, 0x00, 0x80, 0x32, 0xce, 0x5e, 0x0b, 0xdd, 0x6e, 0x5a, 0x0d, 0x0a,
+  0xaf, 0xe1, 0xd6, 0x84, 0xcb, 0xc0, 0x8e, 0xfa, 0x85, 0x70, 0xed, 0xda,
+  0x5d, 0xb3, 0x0c, 0xf7, 0x2b, 0x75, 0x40, 0xfe, 0x85, 0x0a, 0xfa, 0xf3,
+  0x31, 0x78, 0xb7, 0x70, 0x4b, 0x1a, 0x89, 0x58, 0xba, 0x80, 0xbd, 0xf3,
+  0x6b, 0x1d, 0xe9, 0x7e, 0xcf, 0x0b, 0xba, 0x58, 0x9c, 0x59, 0xd4, 0x90,
+  0xd3, 0xfd, 0x6c, 0xfd, 0xd0, 0x98, 0x6d, 0xb7, 0x71, 0x82, 0x5b, 0xcf,
+  0x6d, 0x0b, 0x5a, 0x09, 0xd0, 0x7b, 0xde, 0xc4, 0x43, 0xd8, 0x2a, 0xa4,
+  0xde, 0x9e, 0x41, 0x26, 0x5f, 0xbb, 0x8f, 0x99, 0xcb, 0xdd, 0xae, 0xe1,
+  0xa8, 0x6f, 0x9f, 0x87, 0xfe, 0x74, 0xb7, 0x1f, 0x1b, 0x20, 0xab, 0xb1,
+  0x4f, 0xc6, 0xf5, 0x67, 0x5d, 0x5d, 0x9b, 0x3c, 0xe9, 0xff, 0x69, 0xf7,
+  0x61, 0x6c, 0xd6, 0xd9, 0xf3, 0xfd, 0x36, 0xc6, 0xab, 0x03, 0x88, 0x76,
+  0xd2, 0x4b, 0x2e, 0x75, 0x86, 0xe3, 0xfc, 0xd8, 0x55, 0x7d, 0x26, 0xc2,
+  0x11, 0x77, 0xdf, 0x3e, 0x02, 0xb6, 0x7c, 0xf3, 0xab, 0x7b, 0x7a, 0x86,
+  0x36, 0x6f, 0xb8, 0xf7, 0xd8, 0x93, 0x71, 0xcf, 0x86, 0xdf, 0x73, 0x30,
+  0xfa, 0x7b, 0xab, 0xed, 0x2a, 0x59, 0xc8, 0x42, 0x84, 0x3b, 0x11, 0x17,
+  0x1a, 0x52, 0xf3, 0xc9, 0x0e, 0x14, 0x7d, 0xa2, 0x5b, 0x72, 0x67, 0xba,
+  0x71, 0xed, 0x57, 0x47, 0x66, 0xc5, 0xb8, 0x02, 0x4a, 0x65, 0x34, 0x5e,
+  0x8b, 0xd0, 0x2a, 0x3c, 0x20, 0x9c, 0x51, 0x99, 0x4c, 0xe7, 0x52, 0x9e,
+  0xf7, 0x6b, 0x11, 0x2b, 0x0d, 0x92, 0x7e, 0x1d, 0xe8, 0x8a, 0xeb, 0x36,
+  0x16, 0x43, 0x87, 0xea, 0x2a, 0x63, 0xbf, 0x75, 0x3f, 0xeb, 0xde, 0xc4,
+  0x03, 0xbb, 0x0a, 0x3c, 0xf7, 0x30, 0xef, 0xeb, 0xaf, 0x4c, 0xfc, 0x8b,
+  0x36, 0x10, 0x73, 0x3e, 0xf3, 0xa4
+};
+static const BYTE ocsp_cert_revoked[] = {
+  0x30, 0x82, 0x06, 0x86, 0x30, 0x82, 0x05, 0x6e, 0xa0, 0x03, 0x02, 0x01,
+  0x02, 0x02, 0x10, 0x0d, 0x2e, 0x67, 0xa2, 0x98, 0x85, 0x3b, 0x9a, 0x54,
+  0x52, 0xe3, 0xa2, 0x85, 0xa4, 0x57, 0x2f, 0x30, 0x0d, 0x06, 0x09, 0x2a,
+  0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x30, 0x59,
+  0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55,
+  0x53, 0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c,
+  0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63,
+  0x31, 0x33, 0x30, 0x31, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x2a, 0x52,
+  0x61, 0x70, 0x69, 0x64, 0x53, 0x53, 0x4c, 0x20, 0x54, 0x4c, 0x53, 0x20,
+  0x44, 0x56, 0x20, 0x52, 0x53, 0x41, 0x20, 0x4d, 0x69, 0x78, 0x65, 0x64,
+  0x20, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x20, 0x32, 0x30, 0x32, 0x30,
+  0x20, 0x43, 0x41, 0x2d, 0x31, 0x30, 0x1e, 0x17, 0x0d, 0x32, 0x31, 0x31,
+  0x30, 0x32, 0x37, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x5a, 0x17, 0x0d,
+  0x32, 0x32, 0x31, 0x30, 0x32, 0x37, 0x32, 0x33, 0x35, 0x39, 0x35, 0x39,
+  0x5a, 0x30, 0x1d, 0x31, 0x1b, 0x30, 0x19, 0x06, 0x03, 0x55, 0x04, 0x03,
+  0x13, 0x12, 0x72, 0x65, 0x76, 0x6f, 0x6b, 0x65, 0x64, 0x2e, 0x62, 0x61,
+  0x64, 0x73, 0x73, 0x6c, 0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x82, 0x01, 0x22,
+  0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
+  0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a,
+  0x02, 0x82, 0x01, 0x01, 0x00, 0xb0, 0x76, 0x2d, 0x55, 0x66, 0xdc, 0x72,
+  0x8a, 0xa0, 0x9e, 0x85, 0x92, 0x38, 0x7f, 0x5b, 0xe1, 0x93, 0x8d, 0xad,
+  0x06, 0xc8, 0xad, 0xe9, 0x89, 0xb4, 0xef, 0x1e, 0x77, 0x5b, 0x33, 0x45,
+  0x16, 0x60, 0x7d, 0x33, 0x38, 0x68, 0x04, 0xd7, 0xc9, 0x83, 0x42, 0x83,
+  0xd9, 0x30, 0x4b, 0x54, 0x49, 0x14, 0xca, 0xed, 0xbe, 0x0c, 0x76, 0xba,
+  0x5f, 0xa6, 0x5c, 0x33, 0x78, 0x3f, 0x39, 0xf2, 0x49, 0xa8, 0x88, 0x32,
+  0xee, 0x53, 0x21, 0x14, 0xd3, 0xaa, 0x5c, 0x58, 0x3c, 0x39, 0xcc, 0xf7,
+  0x80, 0xb1, 0x27, 0x1f, 0x54, 0x79, 0x7b, 0x6c, 0x8b, 0xff, 0x41, 0xaa,
+  0x39, 0x24, 0x95, 0x5f, 0x71, 0xbc, 0x49, 0xbf, 0x39, 0x3b, 0xa5, 0xd5,
+  0xe1, 0xa5, 0xde, 0x1d, 0x40, 0x81, 0x25, 0xdc, 0x8a, 0x47, 0x82, 0xfe,
+  0xcd, 0x7c, 0x4b, 0x2c, 0x04, 0xbb, 0xd3, 0x27, 0x56, 0x51, 0xa0, 0x61,
+  0xf2, 0xd2, 0xcb, 0x55, 0x08, 0x25, 0x2a, 0x85, 0xdb, 0x2c, 0x06, 0x8d,
+  0x0d, 0x61, 0xc2, 0x5b, 0x3e, 0x9b, 0x46, 0xdc, 0x58, 0xff, 0x13, 0x27,
+  0xbe, 0x0a, 0x44, 0x1e, 0x68, 0xfe, 0xe1, 0xf6, 0xb7, 0xde, 0x9f, 0x8e,
+  0x6c, 0xc4, 0xb5, 0x19, 0xfa, 0xd7, 0xd3, 0x4f, 0x55, 0xa8, 0x61, 0x79,
+  0xdb, 0x61, 0x2f, 0x6a, 0x9c, 0x2c, 0xf1, 0xc4, 0x81, 0xbb, 0x9e, 0xd2,
+  0x02, 0x05, 0xba, 0x9c, 0x14, 0xa0, 0xf9, 0xf3, 0x54, 0x79, 0x7d, 0x69,
+  0xd9, 0xba, 0x66, 0x1c, 0x87, 0x95, 0x41, 0x50, 0x0e, 0xf9, 0x5e, 0xe1,
+  0xb7, 0xbd, 0xf5, 0x31, 0x24, 0xc5, 0x21, 0x21, 0x03, 0x8a, 0xcf, 0x6d,
+  0x78, 0x58, 0xde, 0xd9, 0x30, 0x7d, 0x03, 0x42, 0x52, 0xd6, 0xb0, 0x1b,
+  0xb9, 0xc9, 0x54, 0x1b, 0x5a, 0xe8, 0xc8, 0x53, 0xf0, 0xac, 0x2b, 0x82,
+  0x10, 0x27, 0xa6, 0xa9, 0x70, 0x25, 0xae, 0xf8, 0xa7, 0x02, 0x03, 0x01,
+  0x00, 0x01, 0xa3, 0x82, 0x03, 0x84, 0x30, 0x82, 0x03, 0x80, 0x30, 0x1f,
+  0x06, 0x03, 0x55, 0x1d, 0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14, 0xa4,
+  0x8d, 0xe5, 0xbe, 0x7c, 0x79, 0xe4, 0x70, 0x23, 0x6d, 0x2e, 0x29, 0x34,
+  0xad, 0x23, 0x58, 0xdc, 0xf5, 0x31, 0x7f, 0x30, 0x1d, 0x06, 0x03, 0x55,
+  0x1d, 0x0e, 0x04, 0x16, 0x04, 0x14, 0xb0, 0xc8, 0xce, 0x20, 0xb2, 0x78,
+  0xcc, 0x1d, 0x23, 0xef, 0xf0, 0xfe, 0xd6, 0x0e, 0x29, 0x4b, 0xac, 0x15,
+  0x72, 0x3c, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x11, 0x04, 0x16, 0x30,
+  0x14, 0x82, 0x12, 0x72, 0x65, 0x76, 0x6f, 0x6b, 0x65, 0x64, 0x2e, 0x62,
+  0x61, 0x64, 0x73, 0x73, 0x6c, 0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x0e, 0x06,
+  0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x05,
+  0xa0, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x25, 0x04, 0x16, 0x30, 0x14,
+  0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x06, 0x08,
+  0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02, 0x30, 0x81, 0x9b, 0x06,
+  0x03, 0x55, 0x1d, 0x1f, 0x04, 0x81, 0x93, 0x30, 0x81, 0x90, 0x30, 0x46,
+  0xa0, 0x44, 0xa0, 0x42, 0x86, 0x40, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f,
+  0x2f, 0x63, 0x72, 0x6c, 0x33, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65,
+  0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x52, 0x61, 0x70, 0x69, 0x64,
+  0x53, 0x53, 0x4c, 0x54, 0x4c, 0x53, 0x44, 0x56, 0x52, 0x53, 0x41, 0x4d,
+  0x69, 0x78, 0x65, 0x64, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x32, 0x30,
+  0x32, 0x30, 0x43, 0x41, 0x2d, 0x31, 0x2e, 0x63, 0x72, 0x6c, 0x30, 0x46,
+  0xa0, 0x44, 0xa0, 0x42, 0x86, 0x40, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f,
+  0x2f, 0x63, 0x72, 0x6c, 0x34, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65,
+  0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x52, 0x61, 0x70, 0x69, 0x64,
+  0x53, 0x53, 0x4c, 0x54, 0x4c, 0x53, 0x44, 0x56, 0x52, 0x53, 0x41, 0x4d,
+  0x69, 0x78, 0x65, 0x64, 0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x32, 0x30,
+  0x32, 0x30, 0x43, 0x41, 0x2d, 0x31, 0x2e, 0x63, 0x72, 0x6c, 0x30, 0x3e,
+  0x06, 0x03, 0x55, 0x1d, 0x20, 0x04, 0x37, 0x30, 0x35, 0x30, 0x33, 0x06,
+  0x06, 0x67, 0x81, 0x0c, 0x01, 0x02, 0x01, 0x30, 0x29, 0x30, 0x27, 0x06,
+  0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x02, 0x01, 0x16, 0x1b, 0x68,
+  0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x64, 0x69,
+  0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x43,
+  0x50, 0x53, 0x30, 0x81, 0x85, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05,
+  0x07, 0x01, 0x01, 0x04, 0x79, 0x30, 0x77, 0x30, 0x24, 0x06, 0x08, 0x2b,
+  0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x01, 0x86, 0x18, 0x68, 0x74, 0x74,
+  0x70, 0x3a, 0x2f, 0x2f, 0x6f, 0x63, 0x73, 0x70, 0x2e, 0x64, 0x69, 0x67,
+  0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x4f, 0x06,
+  0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x02, 0x86, 0x43, 0x68,
+  0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x61, 0x63, 0x65, 0x72, 0x74,
+  0x73, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63,
+  0x6f, 0x6d, 0x2f, 0x52, 0x61, 0x70, 0x69, 0x64, 0x53, 0x53, 0x4c, 0x54,
+  0x4c, 0x53, 0x44, 0x56, 0x52, 0x53, 0x41, 0x4d, 0x69, 0x78, 0x65, 0x64,
+  0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x32, 0x30, 0x32, 0x30, 0x43, 0x41,
+  0x2d, 0x31, 0x2e, 0x63, 0x72, 0x74, 0x30, 0x09, 0x06, 0x03, 0x55, 0x1d,
+  0x13, 0x04, 0x02, 0x30, 0x00, 0x30, 0x82, 0x01, 0x7d, 0x06, 0x0a, 0x2b,
+  0x06, 0x01, 0x04, 0x01, 0xd6, 0x79, 0x02, 0x04, 0x02, 0x04, 0x82, 0x01,
+  0x6d, 0x04, 0x82, 0x01, 0x69, 0x01, 0x67, 0x00, 0x76, 0x00, 0x29, 0x79,
+  0xbe, 0xf0, 0x9e, 0x39, 0x39, 0x21, 0xf0, 0x56, 0x73, 0x9f, 0x63, 0xa5,
+  0x77, 0xe5, 0xbe, 0x57, 0x7d, 0x9c, 0x60, 0x0a, 0xf8, 0xf9, 0x4d, 0x5d,
+  0x26, 0x5c, 0x25, 0x5d, 0xc7, 0x84, 0x00, 0x00, 0x01, 0x7c, 0xc3, 0xa4,
+  0xf7, 0x37, 0x00, 0x00, 0x04, 0x03, 0x00, 0x47, 0x30, 0x45, 0x02, 0x20,
+  0x77, 0xb0, 0x79, 0x18, 0xf3, 0xde, 0x34, 0x70, 0xfa, 0xf2, 0x1b, 0xc2,
+  0x32, 0x39, 0xc8, 0xc8, 0x95, 0xb0, 0xc8, 0x7a, 0x8f, 0x62, 0x23, 0x58,
+  0xdd, 0xad, 0xf9, 0x1b, 0xbe, 0x84, 0x95, 0xed, 0x02, 0x21, 0x00, 0xdd,
+  0x25, 0x68, 0x47, 0xa3, 0x84, 0x5f, 0x95, 0xb1, 0xea, 0xe7, 0xbc, 0x0a,
+  0x09, 0x92, 0xf9, 0x5a, 0x56, 0x72, 0x31, 0xec, 0x07, 0xd6, 0xc6, 0x97,
+  0x4d, 0x4c, 0x7b, 0x90, 0x75, 0x64, 0xae, 0x00, 0x76, 0x00, 0x51, 0xa3,
+  0xb0, 0xf5, 0xfd, 0x01, 0x79, 0x9c, 0x56, 0x6d, 0xb8, 0x37, 0x78, 0x8f,
+  0x0c, 0xa4, 0x7a, 0xcc, 0x1b, 0x27, 0xcb, 0xf7, 0x9e, 0x88, 0x42, 0x9a,
+  0x0d, 0xfe, 0xd4, 0x8b, 0x05, 0xe5, 0x00, 0x00, 0x01, 0x7c, 0xc3, 0xa4,
+  0xf7, 0x64, 0x00, 0x00, 0x04, 0x03, 0x00, 0x47, 0x30, 0x45, 0x02, 0x20,
+  0x4c, 0x22, 0xff, 0x65, 0x39, 0x6b, 0x7e, 0x7b, 0x15, 0x21, 0x79, 0x44,
+  0xc2, 0xeb, 0xb8, 0x4c, 0x2a, 0xc9, 0xa5, 0xc7, 0xac, 0xce, 0x5f, 0x6a,
+  0x5d, 0xe8, 0xb7, 0x24, 0xc5, 0x76, 0xec, 0x19, 0x02, 0x21, 0x00, 0x94,
+  0x5e, 0x02, 0xee, 0x14, 0x60, 0x80, 0x96, 0xbc, 0x0e, 0x39, 0x16, 0x01,
+  0xa8, 0x37, 0x9f, 0x15, 0xb9, 0xb9, 0xba, 0x0f, 0xa2, 0x0c, 0x5a, 0x17,
+  0x90, 0xa5, 0xe1, 0x33, 0x36, 0x45, 0xf2, 0x00, 0x75, 0x00, 0x41, 0xc8,
+  0xca, 0xb1, 0xdf, 0x22, 0x46, 0x4a, 0x10, 0xc6, 0xa1, 0x3a, 0x09, 0x42,
+  0x87, 0x5e, 0x4e, 0x31, 0x8b, 0x1b, 0x03, 0xeb, 0xeb, 0x4b, 0xc7, 0x68,
+  0xf0, 0x90, 0x62, 0x96, 0x06, 0xf6, 0x00, 0x00, 0x01, 0x7c, 0xc3, 0xa4,
+  0xf6, 0xdf, 0x00, 0x00, 0x04, 0x03, 0x00, 0x46, 0x30, 0x44, 0x02, 0x20,
+  0x68, 0x8a, 0x5f, 0x50, 0xb7, 0x76, 0xda, 0x7e, 0x34, 0x32, 0xa5, 0x77,
+  0x02, 0xa6, 0xfa, 0xa7, 0x87, 0xbb, 0xdb, 0x41, 0x5c, 0x80, 0x40, 0x2c,
+  0x05, 0xe5, 0x09, 0xdd, 0x3f, 0xcc, 0x6d, 0x9f, 0x02, 0x20, 0x7b, 0x1d,
+  0x64, 0x48, 0x61, 0x19, 0x75, 0xb6, 0x37, 0xd1, 0x3c, 0x1e, 0x38, 0x78,
+  0x86, 0x7a, 0xf2, 0x79, 0x14, 0x08, 0x42, 0xe8, 0xdd, 0x0f, 0xff, 0x38,
+  0x3a, 0x3c, 0x36, 0xd9, 0xbf, 0xd9, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86,
+  0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x03, 0x82, 0x01,
+  0x01, 0x00, 0xd5, 0x8c, 0xbd, 0xbe, 0xe4, 0xdc, 0x94, 0xa4, 0xb7, 0xf3,
+  0x49, 0xaf, 0xc4, 0x99, 0x26, 0xda, 0x27, 0x68, 0xda, 0xe8, 0xb8, 0xc1,
+  0xba, 0xc6, 0x30, 0xb6, 0x16, 0xaa, 0x50, 0xfe, 0xf4, 0x77, 0x07, 0xeb,
+  0x99, 0xf2, 0xda, 0xdd, 0x77, 0x1d, 0x19, 0x82, 0xf7, 0x24, 0x2a, 0x3b,
+  0xa0, 0x63, 0xe0, 0xdb, 0x09, 0xbe, 0x10, 0x7f, 0xc5, 0x1f, 0x81, 0xba,
+  0xaf, 0x9e, 0x49, 0xce, 0x32, 0x30, 0x49, 0x17, 0x8f, 0x74, 0xc6, 0xd6,
+  0xcd, 0x6a, 0xd8, 0x3b, 0x47, 0x7b, 0xf0, 0xe0, 0x0c, 0xbb, 0xc0, 0x8e,
+  0x3a, 0x1d, 0xa3, 0x7f, 0x92, 0xac, 0x7e, 0x8d, 0xdc, 0xa4, 0xb5, 0x30,
+  0x2a, 0x57, 0x13, 0x23, 0xa7, 0xee, 0x25, 0xc6, 0x37, 0xed, 0x48, 0xb2,
+  0x4a, 0xd0, 0x01, 0xfc, 0x85, 0xe5, 0xc1, 0xe2, 0xe0, 0xdc, 0x8c, 0x61,
+  0x74, 0xaa, 0xaf, 0x68, 0x28, 0x26, 0x45, 0x94, 0xa3, 0xb1, 0x4c, 0xc9,
+  0x5c, 0xc7, 0x92, 0xa2, 0x6c, 0x4a, 0x80, 0x6f, 0xdd, 0x48, 0xfa, 0x4f,
+  0x04, 0xb2, 0x4a, 0x73, 0x17, 0xf2, 0xf9, 0x1e, 0x8e, 0x5c, 0xe9, 0x23,
+  0xec, 0x53, 0xff, 0x3e, 0xc7, 0x8a, 0xb6, 0x18, 0x89, 0xbc, 0x77, 0x45,
+  0x67, 0x4b, 0x9a, 0x73, 0x75, 0x6b, 0x57, 0xc8, 0xc0, 0x6a, 0xcb, 0x84,
+  0x1d, 0xf4, 0xed, 0xef, 0x70, 0x16, 0x77, 0x8e, 0xf3, 0x1a, 0x8e, 0xbb,
+  0x95, 0xf3, 0xeb, 0xf8, 0x5a, 0xe4, 0xa9, 0xb1, 0xdf, 0x1d, 0x36, 0xab,
+  0x0a, 0xdd, 0x91, 0xaf, 0x2d, 0x71, 0x3c, 0xab, 0x97, 0x18, 0x03, 0xdc,
+  0x5c, 0x1a, 0xa9, 0xb1, 0xdb, 0xb6, 0x48, 0x40, 0xc7, 0x19, 0xa7, 0x81,
+  0x14, 0x0b, 0x0d, 0xce, 0x38, 0x6f, 0xda, 0xcf, 0xce, 0x0f, 0x64, 0x13,
+  0x28, 0xf3, 0x4d, 0x67, 0x1b, 0x2c, 0xd1, 0x16, 0x54, 0x19, 0x6f, 0xaa,
+  0x08, 0x54, 0xa3, 0x4d, 0x67, 0x64
+};
+static const BYTE ocsp_cert_revoked_issuer[] = {
+  0x30, 0x82, 0x05, 0x51, 0x30, 0x82, 0x04, 0x39, 0xa0, 0x03, 0x02, 0x01,
+  0x02, 0x02, 0x10, 0x07, 0x98, 0x36, 0x03, 0xad, 0xe3, 0x99, 0x08, 0x21,
+  0x9c, 0xa0, 0x0c, 0x27, 0xbc, 0x8a, 0x6c, 0x30, 0x0d, 0x06, 0x09, 0x2a,
+  0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x30, 0x61,
+  0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55,
+  0x53, 0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c,
+  0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63,
+  0x31, 0x19, 0x30, 0x17, 0x06, 0x03, 0x55, 0x04, 0x0b, 0x13, 0x10, 0x77,
+  0x77, 0x77, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e,
+  0x63, 0x6f, 0x6d, 0x31, 0x20, 0x30, 0x1e, 0x06, 0x03, 0x55, 0x04, 0x03,
+  0x13, 0x17, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x47,
+  0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x20, 0x52, 0x6f, 0x6f, 0x74, 0x20, 0x43,
+  0x41, 0x30, 0x1e, 0x17, 0x0d, 0x32, 0x30, 0x30, 0x37, 0x31, 0x36, 0x31,
+  0x32, 0x32, 0x35, 0x32, 0x37, 0x5a, 0x17, 0x0d, 0x32, 0x33, 0x30, 0x35,
+  0x33, 0x31, 0x32, 0x33, 0x35, 0x39, 0x35, 0x39, 0x5a, 0x30, 0x59, 0x31,
+  0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53,
+  0x31, 0x15, 0x30, 0x13, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0c, 0x44,
+  0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74, 0x20, 0x49, 0x6e, 0x63, 0x31,
+  0x33, 0x30, 0x31, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x2a, 0x52, 0x61,
+  0x70, 0x69, 0x64, 0x53, 0x53, 0x4c, 0x20, 0x54, 0x4c, 0x53, 0x20, 0x44,
+  0x56, 0x20, 0x52, 0x53, 0x41, 0x20, 0x4d, 0x69, 0x78, 0x65, 0x64, 0x20,
+  0x53, 0x48, 0x41, 0x32, 0x35, 0x36, 0x20, 0x32, 0x30, 0x32, 0x30, 0x20,
+  0x43, 0x41, 0x2d, 0x31, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
+  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
+  0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01,
+  0x00, 0xda, 0x6e, 0x43, 0x55, 0x55, 0x99, 0x7b, 0xd9, 0x95, 0xa2, 0x66,
+  0xc4, 0x65, 0x58, 0xa2, 0xd0, 0x0c, 0x17, 0x3a, 0x00, 0xa6, 0x88, 0x5b,
+  0x24, 0x07, 0x8d, 0xa7, 0x33, 0x7e, 0xe3, 0xd2, 0xdb, 0x82, 0x4a, 0xcc,
+  0x2e, 0xfd, 0xad, 0x6e, 0x52, 0x08, 0xf0, 0x7e, 0x37, 0xbc, 0xde, 0xd4,
+  0x16, 0xe9, 0xb1, 0x57, 0xb9, 0x49, 0x74, 0xfc, 0x0b, 0x3f, 0x6d, 0xaa,
+  0x6b, 0x4b, 0x15, 0xf5, 0xcc, 0x02, 0xaf, 0xa4, 0x19, 0xa0, 0x61, 0x28,
+  0x6d, 0xd6, 0xbe, 0xe2, 0x9b, 0x9f, 0x1b, 0x46, 0x92, 0x7c, 0x74, 0x02,
+  0x42, 0x1b, 0xa5, 0x6a, 0xa2, 0xa9, 0x3d, 0xc6, 0x18, 0x38, 0xf8, 0xd3,
+  0xc2, 0x0a, 0x89, 0x03, 0xce, 0x00, 0x15, 0x88, 0xfc, 0x97, 0xf2, 0x1e,
+  0x43, 0xc9, 0xf4, 0xd5, 0x5c, 0x82, 0xba, 0xb3, 0x08, 0x1c, 0x0e, 0x3b,
+  0xf2, 0xdb, 0x36, 0x1b, 0xa1, 0x86, 0xb4, 0x4c, 0x74, 0xb9, 0xc9, 0xc4,
+  0x7d, 0x5d, 0x90, 0x1d, 0x42, 0xfa, 0xe0, 0x40, 0xb6, 0xca, 0x1e, 0xf2,
+  0x6d, 0xba, 0x28, 0xe6, 0xff, 0x27, 0x15, 0x65, 0x78, 0x97, 0x1f, 0xf1,
+  0x71, 0xfc, 0x68, 0xc6, 0x41, 0x53, 0x56, 0x70, 0x08, 0x46, 0x01, 0xeb,
+  0x1f, 0x6b, 0xd4, 0x74, 0xe8, 0x95, 0xf6, 0xc9, 0x4e, 0x8b, 0x1d, 0xf3,
+  0xe4, 0xa3, 0xec, 0xda, 0xb2, 0xb6, 0x6d, 0xb6, 0x9c, 0x87, 0xc4, 0xa1,
+  0xe4, 0x64, 0xa4, 0x82, 0x9d, 0x87, 0x46, 0x84, 0xbf, 0x9b, 0x2d, 0x2d,
+  0x0a, 0xad, 0x6f, 0x8f, 0x22, 0xc9, 0x78, 0xfd, 0x1a, 0x37, 0x03, 0xdd,
+  0xde, 0xb9, 0x39, 0x3b, 0xc2, 0xe2, 0x7d, 0xf2, 0xde, 0xbf, 0xd8, 0xfe,
+  0x50, 0xa6, 0x68, 0xd2, 0xdb, 0x74, 0x56, 0xf4, 0xcb, 0x91, 0xd1, 0xa6,
+  0x48, 0xde, 0x21, 0xd6, 0x65, 0x58, 0xe8, 0x39, 0xc6, 0x7c, 0xec, 0x29,
+  0xd4, 0x2e, 0x52, 0x2b, 0x43, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x82,
+  0x02, 0x0b, 0x30, 0x82, 0x02, 0x07, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d,
+  0x0e, 0x04, 0x16, 0x04, 0x14, 0xa4, 0x8d, 0xe5, 0xbe, 0x7c, 0x79, 0xe4,
+  0x70, 0x23, 0x6d, 0x2e, 0x29, 0x34, 0xad, 0x23, 0x58, 0xdc, 0xf5, 0x31,
+  0x7f, 0x30, 0x1f, 0x06, 0x03, 0x55, 0x1d, 0x23, 0x04, 0x18, 0x30, 0x16,
+  0x80, 0x14, 0x03, 0xde, 0x50, 0x35, 0x56, 0xd1, 0x4c, 0xbb, 0x66, 0xf0,
+  0xa3, 0xe2, 0x1b, 0x1b, 0xc3, 0x97, 0xb2, 0x3d, 0xd1, 0x55, 0x30, 0x0e,
+  0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02,
+  0x01, 0x86, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x25, 0x04, 0x16, 0x30,
+  0x14, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x06,
+  0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02, 0x30, 0x12, 0x06,
+  0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x08, 0x30, 0x06, 0x01,
+  0x01, 0xff, 0x02, 0x01, 0x00, 0x30, 0x34, 0x06, 0x08, 0x2b, 0x06, 0x01,
+  0x05, 0x05, 0x07, 0x01, 0x01, 0x04, 0x28, 0x30, 0x26, 0x30, 0x24, 0x06,
+  0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x01, 0x86, 0x18, 0x68,
+  0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x6f, 0x63, 0x73, 0x70, 0x2e, 0x64,
+  0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x30,
+  0x7b, 0x06, 0x03, 0x55, 0x1d, 0x1f, 0x04, 0x74, 0x30, 0x72, 0x30, 0x37,
+  0xa0, 0x35, 0xa0, 0x33, 0x86, 0x31, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f,
+  0x2f, 0x63, 0x72, 0x6c, 0x33, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65,
+  0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43,
+  0x65, 0x72, 0x74, 0x47, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x52, 0x6f, 0x6f,
+  0x74, 0x43, 0x41, 0x2e, 0x63, 0x72, 0x6c, 0x30, 0x37, 0xa0, 0x35, 0xa0,
+  0x33, 0x86, 0x31, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x63, 0x72,
+  0x6c, 0x34, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e,
+  0x63, 0x6f, 0x6d, 0x2f, 0x44, 0x69, 0x67, 0x69, 0x43, 0x65, 0x72, 0x74,
+  0x47, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x52, 0x6f, 0x6f, 0x74, 0x43, 0x41,
+  0x2e, 0x63, 0x72, 0x6c, 0x30, 0x81, 0xce, 0x06, 0x03, 0x55, 0x1d, 0x20,
+  0x04, 0x81, 0xc6, 0x30, 0x81, 0xc3, 0x30, 0x81, 0xc0, 0x06, 0x04, 0x55,
+  0x1d, 0x20, 0x00, 0x30, 0x81, 0xb7, 0x30, 0x28, 0x06, 0x08, 0x2b, 0x06,
+  0x01, 0x05, 0x05, 0x07, 0x02, 0x01, 0x16, 0x1c, 0x68, 0x74, 0x74, 0x70,
+  0x73, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x64, 0x69, 0x67, 0x69,
+  0x63, 0x65, 0x72, 0x74, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x43, 0x50, 0x53,
+  0x30, 0x81, 0x8a, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x02,
+  0x02, 0x30, 0x7e, 0x0c, 0x7c, 0x41, 0x6e, 0x79, 0x20, 0x75, 0x73, 0x65,
+  0x20, 0x6f, 0x66, 0x20, 0x74, 0x68, 0x69, 0x73, 0x20, 0x43, 0x65, 0x72,
+  0x74, 0x69, 0x66, 0x69, 0x63, 0x61, 0x74, 0x65, 0x20, 0x63, 0x6f, 0x6e,
+  0x73, 0x74, 0x69, 0x74, 0x75, 0x74, 0x65, 0x73, 0x20, 0x61, 0x63, 0x63,
+  0x65, 0x70, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x20, 0x6f, 0x66, 0x20, 0x74,
+  0x68, 0x65, 0x20, 0x52, 0x65, 0x6c, 0x79, 0x69, 0x6e, 0x67, 0x20, 0x50,
+  0x61, 0x72, 0x74, 0x79, 0x20, 0x41, 0x67, 0x72, 0x65, 0x65, 0x6d, 0x65,
+  0x6e, 0x74, 0x20, 0x6c, 0x6f, 0x63, 0x61, 0x74, 0x65, 0x64, 0x20, 0x61,
+  0x74, 0x20, 0x68, 0x74, 0x74, 0x70, 0x73, 0x3a, 0x2f, 0x2f, 0x77, 0x77,
+  0x77, 0x2e, 0x64, 0x69, 0x67, 0x69, 0x63, 0x65, 0x72, 0x74, 0x2e, 0x63,
+  0x6f, 0x6d, 0x2f, 0x72, 0x70, 0x61, 0x2d, 0x75, 0x61, 0x30, 0x0d, 0x06,
+  0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00,
+  0x03, 0x82, 0x01, 0x01, 0x00, 0x22, 0xe3, 0xdc, 0x6d, 0x48, 0xeb, 0x8e,
+  0xca, 0x00, 0x72, 0x73, 0x2e, 0x74, 0xaa, 0xe0, 0x93, 0x84, 0x6e, 0x39,
+  0xc4, 0x87, 0x54, 0x02, 0xc4, 0x02, 0x69, 0x71, 0x55, 0x45, 0xaf, 0x5a,
+  0xb0, 0xf6, 0x81, 0xfe, 0x32, 0xc8, 0x35, 0x72, 0x4b, 0xde, 0xa5, 0x7d,
+  0x27, 0x41, 0xa1, 0xd9, 0xb6, 0x4c, 0xd2, 0x4e, 0x32, 0x38, 0xc7, 0x80,
+  0x31, 0x9e, 0x7b, 0xb2, 0x63, 0xfa, 0x26, 0x47, 0x09, 0x8a, 0x18, 0x4e,
+  0x16, 0x57, 0xd0, 0x6b, 0x5f, 0x1a, 0x96, 0x37, 0x7e, 0xc4, 0xd7, 0x3a,
+  0x6f, 0xe1, 0x97, 0xea, 0x81, 0x5c, 0x08, 0x71, 0xab, 0xfa, 0x0b, 0x04,
+  0xc8, 0xf3, 0x3c, 0xaa, 0xf9, 0x4a, 0x1b, 0x17, 0x39, 0x4f, 0x97, 0x87,
+  0x57, 0x35, 0x7a, 0x8e, 0x98, 0xe9, 0xcb, 0x39, 0x7a, 0x54, 0x42, 0xa9,
+  0x6b, 0x11, 0xfa, 0x81, 0xd1, 0x95, 0xa5, 0x05, 0x60, 0x8e, 0x43, 0x91,
+  0xf7, 0x26, 0x3d, 0x5c, 0x05, 0x25, 0x16, 0x7c, 0xe5, 0x38, 0x2a, 0x6a,
+  0xb2, 0x6e, 0xeb, 0xd9, 0x95, 0x0a, 0xa4, 0x37, 0xeb, 0x85, 0x49, 0xd5,
+  0xcd, 0x7d, 0xa7, 0x48, 0xcd, 0x79, 0x5d, 0x28, 0xf8, 0xf2, 0xb5, 0x41,
+  0x04, 0x09, 0xc6, 0x25, 0x69, 0x0b, 0x3e, 0x28, 0xe5, 0x00, 0x27, 0x77,
+  0xb1, 0x61, 0x4c, 0x55, 0x48, 0x8a, 0x47, 0x3d, 0x42, 0xe4, 0xf6, 0x72,
+  0x7a, 0x5d, 0xa5, 0xec, 0x9f, 0xd6, 0xe1, 0xdf, 0x7d, 0x28, 0x52, 0xd2,
+  0x62, 0x0a, 0x32, 0xe4, 0x60, 0xe6, 0x01, 0x1a, 0x70, 0x2d, 0xcf, 0xff,
+  0x7d, 0x77, 0xe4, 0xaf, 0x8d, 0x27, 0x31, 0x8f, 0x22, 0x6c, 0x29, 0xb1,
+  0x0a, 0xc8, 0xd7, 0x41, 0x37, 0xb4, 0x7c, 0x96, 0xed, 0xae, 0xb2, 0xcb,
+  0xc9, 0x64, 0x25, 0x93, 0xd5, 0x43, 0x57, 0x6f, 0x7a, 0x10, 0x8f, 0xe4,
+  0x40, 0xe2, 0x4d, 0x2d, 0x51, 0x24, 0x27, 0x9e, 0x0f
+};
static void testVerifyRevocation(void)
{
     BOOL ret;
@@ -3643,6 +4157,44 @@ static void testVerifyRevocation(void)
     CertCloseStore(revPara.hCrlStore, 0);
     CertFreeCertificateContext(certs[1]);
     CertFreeCertificateContext(certs[0]);
+    /* OCSP */
+    certs[0] = CertCreateCertificateContext(X509_ASN_ENCODING, ocsp_cert, sizeof(ocsp_cert));
+    memset(&revPara, 0, sizeof(revPara));
+    revPara.cbSize = sizeof(revPara);
+    memset(&status, 0x55, sizeof(status));
+    status.cbSize = sizeof(status);
+    SetLastError(0xdeadbeef);
+    ret = CertVerifyRevocation(X509_ASN_ENCODING, CERT_CONTEXT_REVOCATION_TYPE, 1, (void **)&certs[0],
+                               0, &revPara, &status);
+    ok(!ret, "success\n");
+    ok(GetLastError() == CRYPT_E_REVOCATION_OFFLINE, "got %08lx\n", GetLastError());
+    revPara.pIssuerCert = CertCreateCertificateContext(X509_ASN_ENCODING, ocsp_cert_issuer,
+                                                       sizeof(ocsp_cert_issuer));
+    ret = CertVerifyRevocation(X509_ASN_ENCODING, CERT_CONTEXT_REVOCATION_TYPE, 1, (void **)&certs[0],
+                               0, &revPara, &status);
+    ok(ret, "got %08lx\n", GetLastError());
+    ok(!status.dwError, "got %08lx\n", status.dwError);
+    ok(!status.dwIndex, "got %ld\n", status.dwIndex);
+    CertFreeCertificateContext(revPara.pIssuerCert);
+    CertFreeCertificateContext(certs[0]);
+    certs[0] = CertCreateCertificateContext(X509_ASN_ENCODING, ocsp_cert_revoked, sizeof(ocsp_cert_revoked));
+    revPara.pIssuerCert = CertCreateCertificateContext(X509_ASN_ENCODING, ocsp_cert_revoked_issuer,
+                                                       sizeof(ocsp_cert_revoked_issuer));
+    memset(&status, 0x55, sizeof(status));
+    status.cbSize = sizeof(status);
+    SetLastError(0xdeadbeef);
+    ret = CertVerifyRevocation(X509_ASN_ENCODING, CERT_CONTEXT_REVOCATION_TYPE, 1, (void **)&certs[0],
+                               0, &revPara, &status);
+    ok(!ret, "success\n");
+    ok(GetLastError() == CRYPT_E_REVOKED, "got %08lx\n", GetLastError());
+    ok(status.dwError == CRYPT_E_REVOKED, "got %08lx\n", status.dwError);
+    ok(!status.dwIndex, "got %ld\n", status.dwIndex);
+    ok(!status.dwReason, "got %lu\n", status.dwReason);
+    CertFreeCertificateContext(revPara.pIssuerCert);
+    CertFreeCertificateContext(certs[0]);
}

static BYTE privKey[] = {
@@ -3753,45 +4305,42 @@ static void testAcquireCertPrivateKey(void)
          CERT_KEY_CONTEXT keyContext;

          /* Don't cache provider */
+        SetLastError(0xdeadbeef);
          ret = CryptAcquireCertificatePrivateKey(cert, 0, NULL, &certCSP,
          &keySpec, &callerFree);
-        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n",
-         GetLastError());
-        if (ret)
-        {
-            ok(callerFree, "Expected callerFree to be TRUE\n");
-            CryptReleaseContext(certCSP, 0);
-        }
+        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n", GetLastError());
+        ok(GetLastError() == ERROR_SUCCESS, "got %08lx\n", GetLastError());
+        ok(callerFree, "Expected callerFree to be TRUE\n");
+        CryptReleaseContext(certCSP, 0);

+        SetLastError(0xdeadbeef);
          ret = CryptAcquireCertificatePrivateKey(cert, 0, NULL, &certCSP,
          NULL, NULL);
-        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n",
-         GetLastError());
+        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n", GetLastError());
+        ok(GetLastError() == ERROR_SUCCESS, "got %08lx\n", GetLastError());
          CryptReleaseContext(certCSP, 0);

          /* Use the key prov info's caching (there shouldn't be any) */
+        SetLastError(0xdeadbeef);
          ret = CryptAcquireCertificatePrivateKey(cert,
          CRYPT_ACQUIRE_USE_PROV_INFO_FLAG, NULL, &certCSP, &keySpec,
          &callerFree);
-        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n",
-         GetLastError());
-        if (ret)
-        {
-            ok(callerFree, "Expected callerFree to be TRUE\n");
-            CryptReleaseContext(certCSP, 0);
-        }
+        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n", GetLastError());
+        ok(GetLastError() == ERROR_SUCCESS, "got %08lx\n", GetLastError());
+        ok(callerFree, "Expected callerFree to be TRUE\n");
+        CryptReleaseContext(certCSP, 0);

          /* Cache it (and check that it's cached) */
+        SetLastError(0xdeadbeef);
          ret = CryptAcquireCertificatePrivateKey(cert,
          CRYPT_ACQUIRE_CACHE_FLAG, NULL, &certCSP, &keySpec, &callerFree);
-        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n",
-         GetLastError());
+        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n", GetLastError());
+        ok(GetLastError() == ERROR_SUCCESS, "got %08lx\n", GetLastError());
          ok(!callerFree, "Expected callerFree to be FALSE\n");
          size = sizeof(keyContext);
          ret = CertGetCertificateContextProperty(cert, CERT_KEY_CONTEXT_PROP_ID,
          &keyContext, &size);
-        ok(ret, "CertGetCertificateContextProperty failed: %08lx\n",
-         GetLastError());
+        ok(ret, "CertGetCertificateContextProperty failed: %08lx\n", GetLastError());

          /* Remove the cached provider */
          CryptReleaseContext(keyContext.hCryptProv, 0);
@@ -3802,17 +4351,17 @@ static void testAcquireCertPrivateKey(void)
          CertSetCertificateContextProperty(cert, CERT_KEY_PROV_INFO_PROP_ID, 0,
          &keyProvInfo);
          /* Now use the key prov info's caching */
+        SetLastError(0xdeadbeef);
          ret = CryptAcquireCertificatePrivateKey(cert,
          CRYPT_ACQUIRE_USE_PROV_INFO_FLAG, NULL, &certCSP, &keySpec,
          &callerFree);
-        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n",
-         GetLastError());
+        ok(ret, "CryptAcquireCertificatePrivateKey failed: %08lx\n", GetLastError());
+        ok(GetLastError() == ERROR_SUCCESS, "got %08lx\n", GetLastError());
          ok(!callerFree, "Expected callerFree to be FALSE\n");
          size = sizeof(keyContext);
          ret = CertGetCertificateContextProperty(cert, CERT_KEY_CONTEXT_PROP_ID,
          &keyContext, &size);
-        ok(ret, "CertGetCertificateContextProperty failed: %08lx\n",
-         GetLastError());
+        ok(ret, "CertGetCertificateContextProperty failed: %08lx\n", GetLastError());
          CryptReleaseContext(certCSP, 0);

          CryptDestroyKey(key);
@@ -3828,7 +4377,7 @@ static void testAcquireCertPrivateKey(void)
          ok(ret, "CryptExportKey failed: %08lx\n", GetLastError());
          if (ret)
          {
-            LPBYTE buf = HeapAlloc(GetProcessHeap(), 0, size), encodedKey;
+            LPBYTE buf = malloc(size), encodedKey;

               ret = CryptExportKey(key, 0, PUBLICKEYBLOB, 0, buf, &size);
               ok(ret, "CryptExportKey failed: %08lx\n", GetLastError());
@@ -3846,7 +4395,7 @@ static void testAcquireCertPrivateKey(void)
                    "Unexpected value\n");
               LocalFree(encodedKey);
               }
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          CryptDestroyKey(key);
     }
@@ -3855,7 +4404,7 @@ static void testAcquireCertPrivateKey(void)
     ok(ret, "CryptExportPublicKeyInfoEx failed: %08lx\n", GetLastError());
     if (ret)
     {
-        PCERT_PUBLIC_KEY_INFO info = HeapAlloc(GetProcessHeap(), 0, size);
+        PCERT_PUBLIC_KEY_INFO info = malloc(size);

          ret = CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE, X509_ASN_ENCODING,
          NULL, 0, NULL, info, &size);
@@ -3867,7 +4416,7 @@ static void testAcquireCertPrivateKey(void)
               ok(!memcmp(info->PublicKey.pbData, asnEncodedPublicKey,
               info->PublicKey.cbData), "Unexpected value\n");
          }
-        HeapFree(GetProcessHeap(), 0, info);
+        free(info);
     }

     CryptReleaseContext(csp, 0);
@@ -3992,7 +4541,7 @@ static void testKeyProvInfo(void)

     ret = CertGetCertificateContextProperty(cert, CERT_KEY_PROV_INFO_PROP_ID, NULL, &size);
     ok(ret, "CertGetCertificateContextProperty error %#lx\n", GetLastError());
-    info = HeapAlloc(GetProcessHeap(), 0, size);
+    info = malloc(size);
     ret = CertGetCertificateContextProperty(cert, CERT_KEY_PROV_INFO_PROP_ID, info, &size);
     ok(ret, "CertGetCertificateContextProperty error %#lx\n", GetLastError());
     ok(!lstrcmpW(info->pwszContainerName, containerW), "got %s\n", wine_dbgstr_w(info->pwszContainerName));
@@ -4010,7 +4559,7 @@ static void testKeyProvInfo(void)
     ok(info->rgProvParam[1].cbData == param[1].cbData, "got %#lx\n", info->rgProvParam[1].cbData);
     ok(!memcmp(info->rgProvParam[1].pbData, param[1].pbData, param[1].cbData), "param2 mismatch\n");
     ok(info->rgProvParam[1].dwFlags == param[1].dwFlags, "got %#lx\n", info->rgProvParam[1].dwFlags);
-    HeapFree(GetProcessHeap(), 0, info);
+    free(info);

     ret = CertAddCertificateContextToStore(store, cert, CERT_STORE_ADD_NEW, NULL);
     ok(ret, "CertAddCertificateContextToStore error %#lx\n", GetLastError());
@@ -4029,7 +4578,7 @@ static void testKeyProvInfo(void)

     ret = CertGetCertificateContextProperty(cert, CERT_KEY_PROV_INFO_PROP_ID, NULL, &size);
     ok(ret, "CertGetCertificateContextProperty error %#lx\n", GetLastError());
-    info = HeapAlloc(GetProcessHeap(), 0, size);
+    info = malloc(size);
     ret = CertGetCertificateContextProperty(cert, CERT_KEY_PROV_INFO_PROP_ID, info, &size);
     ok(ret, "CertGetCertificateContextProperty error %#lx\n", GetLastError());
     ok(!lstrcmpW(info->pwszContainerName, containerW), "got %s\n", wine_dbgstr_w(info->pwszContainerName));
@@ -4047,7 +4596,7 @@ static void testKeyProvInfo(void)
     ok(info->rgProvParam[1].cbData == param[1].cbData, "got %#lx\n", info->rgProvParam[1].cbData);
     ok(!memcmp(info->rgProvParam[1].pbData, param[1].pbData, param[1].cbData), "param2 mismatch\n");
     ok(info->rgProvParam[1].dwFlags == param[1].dwFlags, "got %#lx\n", info->rgProvParam[1].dwFlags);
-    HeapFree(GetProcessHeap(), 0, info);
+    free(info);

     ret = CertDeleteCertificateFromStore(cert);
     ok(ret, "CertDeleteCertificateFromStore error %#lx\n", GetLastError());
@@ -4126,7 +4675,7 @@ static void test_VerifySignature(void)
     ok(!status, "got %#lx\n", status);
     ok(hash_len == sizeof(hash_value), "got %lu\n", hash_len);

-    sig_value = HeapAlloc(GetProcessHeap(), 0, info->Signature.cbData);
+    sig_value = malloc(info->Signature.cbData);
     for (i = 0; i < info->Signature.cbData; i++)
          sig_value[i] = info->Signature.pbData[info->Signature.cbData - i - 1];

@@ -4134,7 +4683,7 @@ static void test_VerifySignature(void)
     status = BCryptVerifySignature(bkey, &pad, hash_value, sizeof(hash_value), sig_value, info->Signature.cbData, BCRYPT_PAD_PKCS1);
     ok(!status, "got %#lx\n", status);

-    HeapFree(GetProcessHeap(), 0, sig_value);
+    free(sig_value);
     BCryptDestroyHash(bhash);
     BCryptCloseAlgorithmProvider(alg, 0);
     BCryptDestroyKey(bkey);
diff --git a/wine/dlls/crypt32/tests/chain.c b/wine/dlls/crypt32/tests/chain.c
index 9ed1b28bf..32f008017 100644
--- a/wine/dlls/crypt32/tests/chain.c
+++ b/wine/dlls/crypt32/tests/chain.c
@@ -4958,6 +4958,13 @@ static const ChainPolicyCheck msRootPolicyCheck[] = {
     { 0, CERT_E_UNTRUSTEDROOT, 0, 0, NULL }, NULL, 0 },
};

+static const ChainPolicyCheck msRootPolicyCheck_approot[] = {
+ { { ARRAY_SIZE(chain32), chain32 },
+   { 0, CERT_E_UNTRUSTEDROOT, 0, 2, NULL }, NULL, TODO_ELEMENTS },
+ { { ARRAY_SIZE(chain33), chain33 },
+   { 0, 0, 0, 0, NULL }, NULL, 0 },
+};
static const char *num_to_str(WORD num)
{
     static char buf[6];
@@ -5295,8 +5302,16 @@ static void check_ssl_policy(void)

static void check_msroot_policy(void)
{
+    CERT_CHAIN_POLICY_PARA para;
     CHECK_CHAIN_POLICY_STATUS_ARRAY(CERT_CHAIN_POLICY_MICROSOFT_ROOT, NULL,
     msRootPolicyCheck, &may2020, NULL);
+    para.cbSize = sizeof(para);
+    para.pvExtraPolicyPara = NULL;
+    para.dwFlags = MICROSOFT_ROOT_CERT_CHAIN_POLICY_CHECK_APPLICATION_ROOT_FLAG;
+    CHECK_CHAIN_POLICY_STATUS_ARRAY(CERT_CHAIN_POLICY_MICROSOFT_ROOT, NULL,
+     msRootPolicyCheck_approot, &may2020, &para);
}

static void testVerifyCertChainPolicy(void)
diff --git a/wine/dlls/crypt32/tests/encode.c b/wine/dlls/crypt32/tests/encode.c
index 9dabe58ef..527e66386 100644
--- a/wine/dlls/crypt32/tests/encode.c
+++ b/wine/dlls/crypt32/tests/encode.c
@@ -2315,10 +2315,10 @@ static const BYTE modulus1[] = { 0,0,0,1,1,1,1,1 };
static const BYTE modulus2[] = { 1,1,1,1,1,0,0,0 };
static const BYTE modulus3[] = { 0x80,1,1,1,1,0,0,0 };
static const BYTE modulus4[] = { 1,1,1,1,1,0,0,0x80 };
-static const BYTE mod1_encoded[] = { 0x30,0x0f,0x02,0x08,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x02,0x03,0x01,0x00,0x01 };
-static const BYTE mod2_encoded[] = { 0x30,0x0c,0x02,0x05,0x01,0x01,0x01,0x01,0x01,0x02,0x03,0x01,0x00,0x01 };
-static const BYTE mod3_encoded[] = { 0x30,0x0c,0x02,0x05,0x01,0x01,0x01,0x01,0x80,0x02,0x03,0x01,0x00,0x01 };
-static const BYTE mod4_encoded[] = { 0x30,0x10,0x02,0x09,0x00,0x80,0x00,0x00,0x01,0x01,0x01,0x01,0x01,0x02,0x03,0x01,0x00,0x01 };
+static const BYTE mod1_encoded[] = { 0x30,0x0f,0x02,0x08,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x02,0x03,0x02,0x00,0x01 };
+static const BYTE mod2_encoded[] = { 0x30,0x0c,0x02,0x05,0x01,0x01,0x01,0x01,0x01,0x02,0x03,0x02,0x00,0x01 };
+static const BYTE mod3_encoded[] = { 0x30,0x0c,0x02,0x05,0x01,0x01,0x01,0x01,0x80,0x02,0x03,0x02,0x00,0x01 };
+static const BYTE mod4_encoded[] = { 0x30,0x10,0x02,0x09,0x00,0x80,0x00,0x00,0x01,0x01,0x01,0x01,0x01,0x02,0x03,0x02,0x00,0x01 };

struct EncodedRSAPubKey
{
@@ -2351,7 +2351,7 @@ static void test_encodeRsaPublicKey(DWORD dwEncoding)
     hdr->aiKeyAlg = CALG_RSA_KEYX;
     rsaPubKey->magic = 0x31415352;
     rsaPubKey->bitlen = sizeof(modulus1) * 8;
-    rsaPubKey->pubexp = 65537;
+    rsaPubKey->pubexp = 131073;
     memcpy(toEncode + sizeof(BLOBHEADER) + sizeof(RSAPUBKEY), modulus1,
     sizeof(modulus1));

@@ -2480,7 +2480,7 @@ static void test_decodeRsaPublicKey(DWORD dwEncoding)
               "Expected magic RSA1, got %08lx\n", rsaPubKey->magic);
               ok(rsaPubKey->bitlen == rsaPubKeys[i].decodedModulusLen * 8,
               "Wrong bit len %ld\n", rsaPubKey->bitlen);
-            ok(rsaPubKey->pubexp == 65537, "Expected pubexp 65537, got %ld\n",
+            ok(rsaPubKey->pubexp == 131073, "Expected pubexp 131073, got %ld\n",
               rsaPubKey->pubexp);
               ok(!memcmp(buf + sizeof(BLOBHEADER) + sizeof(RSAPUBKEY),
               rsaPubKeys[i].modulus, rsaPubKeys[i].decodedModulusLen),
@@ -2497,7 +2497,7 @@ static void test_encodeRsaPublicKey_Bcrypt(DWORD dwEncoding)
     BOOL ret;
     BYTE *buf = NULL;
     DWORD bufSize = 0, i;
-    BYTE pubexp[] = {0x01,0x00,0x01,0x00}; /* 65537 */
+    BYTE pubexp[] = {0x01,0x00,0x02,0x00}; /* 131073 */

     /* Verify that the Magic value doesn't matter */
     hdr->Magic = 1;
@@ -2568,7 +2568,7 @@ static void test_decodeRsaPublicKey_Bcrypt(DWORD dwEncoding)
          if (ret)
          {
               BCRYPT_RSAKEY_BLOB *hdr = (BCRYPT_RSAKEY_BLOB *)buf;
-            BYTE pubexp[] = {0xff,0xff,0xff,0xff}, pubexp_expected[] = {0x01,0x00,0x01};
+            BYTE pubexp[] = {0xff,0xff,0xff,0xcc}, pubexp_expected[] = {0x01,0x00,0x02};
               /* CNG_RSA_PUBLIC_KEY_BLOB stores the exponent
               * in big-endian format, so we need to convert it to little-endian
               */
@@ -2584,15 +2584,15 @@ static void test_decodeRsaPublicKey_Bcrypt(DWORD dwEncoding)
               /* Windows decodes the exponent to 3 bytes, since it will fit.
               * Our implementation currently unconditionally decodes to a DWORD (4 bytes)
               */
-            todo_wine ok(hdr->cbPublicExp == 3, "Expected cbPublicExp 3, got %ld\n", hdr->cbPublicExp);
+            ok(hdr->cbPublicExp == 3, "Expected cbPublicExp 3, got %ld\n", hdr->cbPublicExp);
               ok(hdr->cbModulus == rsaPubKeys[i].decodedModulusLen,
               "Wrong modulus len %ld\n", hdr->cbModulus);
               ok(hdr->cbPrime1 == 0,"Wrong cbPrime1 %ld\n", hdr->cbPrime1);
               ok(hdr->cbPrime2 == 0,"Wrong cbPrime2 %ld\n", hdr->cbPrime2);
               ok(!memcmp(pubexp, pubexp_expected, sizeof(pubexp_expected)), "Wrong exponent\n");
-            todo_wine ok(pubexp[3] == 0xff, "Got %02x\n", pubexp[3]);
+            ok(pubexp[3] == 0xcc, "Got %02x\n", pubexp[3]);

-            leModulus = HeapAlloc(GetProcessHeap(), 0, hdr->cbModulus);
+            leModulus = malloc(hdr->cbModulus);
               /*
               * CNG_RSA_PUBLIC_KEY_BLOB stores the modulus in big-endian format,
               * so we need to convert it to little-endian
@@ -2603,7 +2603,7 @@ static void test_decodeRsaPublicKey_Bcrypt(DWORD dwEncoding)
               rsaPubKeys[i].modulus, rsaPubKeys[i].decodedModulusLen),
               "Unexpected modulus\n");
               LocalFree(buf);
-            LocalFree(leModulus);
+            free(leModulus);
          }
     }
}
@@ -2799,13 +2799,13 @@ static void test_decodeExtensions(DWORD dwEncoding)
          ret = CryptDecodeObjectEx(dwEncoding, X509_EXTENSIONS,
          exts[i].encoded, exts[i].encoded[1] + 2, 0, NULL, NULL, &bufSize);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, bufSize);
+        buf = calloc(1, bufSize);
          if (buf)
          {
               ret = CryptDecodeObjectEx(dwEncoding, X509_EXTENSIONS,
               exts[i].encoded, exts[i].encoded[1] + 2, 0, NULL, buf, &bufSize);
               ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
     }
}
@@ -3770,14 +3770,14 @@ static void test_decodeCRLDistPoints(DWORD dwEncoding)
     distPointWithUrlAndIssuer, distPointWithUrlAndIssuer[1] + 2, 0,
     NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    buf = calloc(1, size);
     if (buf)
     {
          ret = CryptDecodeObjectEx(dwEncoding, X509_CRL_DIST_POINTS,
          distPointWithUrlAndIssuer, distPointWithUrlAndIssuer[1] + 2, 0,
          NULL, buf, &size);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, buf);
+        free(buf);
     }
}

@@ -4906,13 +4906,13 @@ static void test_decodeEnhancedKeyUsage(DWORD dwEncoding)
     ret = CryptDecodeObjectEx(dwEncoding, X509_ENHANCED_KEY_USAGE,
     encodedUsage, sizeof(encodedUsage), 0, NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    buf = calloc(1, size);
     if (buf)
     {
          ret = CryptDecodeObjectEx(dwEncoding, X509_ENHANCED_KEY_USAGE,
          encodedUsage, sizeof(encodedUsage), 0, NULL, buf, &size);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, buf);
+        free(buf);
     }
}

@@ -5391,14 +5391,14 @@ static void test_decodeAuthorityInfoAccess(DWORD dwEncoding)
     authorityInfoAccessWithUrlAndIPAddr,
     sizeof(authorityInfoAccessWithUrlAndIPAddr), 0, NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %lx\n", GetLastError());
-    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    buf = calloc(1, size);
     if (buf)
     {
          ret = CryptDecodeObjectEx(dwEncoding, X509_AUTHORITY_INFO_ACCESS,
          authorityInfoAccessWithUrlAndIPAddr,
          sizeof(authorityInfoAccessWithUrlAndIPAddr), 0, NULL, buf, &size);
          ok(ret, "CryptDecodeObjectEx failed: %lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, buf);
+        free(buf);
     }
}

@@ -6354,13 +6354,13 @@ static void test_decodePKCSAttributes(DWORD dwEncoding)
     ret = CryptDecodeObjectEx(dwEncoding, PKCS_ATTRIBUTES,
     doublePKCSAttributes, sizeof(doublePKCSAttributes), 0, NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %lx\n", GetLastError());
-    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    buf = calloc(1, size);
     if (buf)
     {
          ret = CryptDecodeObjectEx(dwEncoding, PKCS_ATTRIBUTES,
          doublePKCSAttributes, sizeof(doublePKCSAttributes), 0, NULL, buf, &size);
          ok(ret, "CryptDecodeObjectEx failed: %lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, buf);
+        free(buf);
     }
}

@@ -6522,14 +6522,14 @@ static void test_decodePKCSSMimeCapabilities(DWORD dwEncoding)
     ret = CryptDecodeObjectEx(dwEncoding, PKCS_SMIME_CAPABILITIES,
     twoCapabilities, sizeof(twoCapabilities), 0, NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-    ptr = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    ptr = calloc(1, size);
     if (ptr)
     {
          SetLastError(0xdeadbeef);
          ret = CryptDecodeObjectEx(dwEncoding, PKCS_SMIME_CAPABILITIES,
          twoCapabilities, sizeof(twoCapabilities), 0, NULL, ptr, &size);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, ptr);
+        free(ptr);
     }
}

@@ -7645,13 +7645,13 @@ static void test_decodeCertPolicies(DWORD dwEncoding)
     ret = CryptDecodeObjectEx(dwEncoding, X509_CERT_POLICIES,
     twoPolicies, sizeof(twoPolicies), 0, NULL, NULL, &size);
     ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-    info = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+    info = calloc(1, size);
     if (info)
     {
          ret = CryptDecodeObjectEx(dwEncoding, X509_CERT_POLICIES,
          twoPolicies, sizeof(twoPolicies), 0, NULL, info, &size);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        HeapFree(GetProcessHeap(), 0, info);
+        free(info);
     }
}

@@ -7788,14 +7788,14 @@ static void test_decodeCertPolicyMappings(DWORD dwEncoding)
          policyMappingWithTwoMappings, sizeof(policyMappingWithTwoMappings), 0,
          NULL, NULL, &size);
          ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-        info = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
+        info = calloc(1, size);
          if (info)
          {
               ret = CryptDecodeObjectEx(dwEncoding, mappingOids[i],
               policyMappingWithTwoMappings, sizeof(policyMappingWithTwoMappings), 0,
               NULL, info, &size);
               ok(ret, "CryptDecodeObjectEx failed: %08lx\n", GetLastError());
-            HeapFree(GetProcessHeap(), 0, info);
+            free(info);
          }
     }
}
@@ -8225,7 +8225,6 @@ static void test_decodeRsaPrivateKey(DWORD dwEncoding)
     }
}

-/* Free *pInfo with HeapFree */
static void testExportPublicKey(HCRYPTPROV csp, PCERT_PUBLIC_KEY_INFO *pInfo)
{
     BOOL ret;
@@ -8262,7 +8261,7 @@ static void testExportPublicKey(HCRYPTPROV csp, PCERT_PUBLIC_KEY_INFO *pInfo)
          ret = CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE, X509_ASN_ENCODING,
          NULL, 0, NULL, NULL, &size);
          ok(ret, "CryptExportPublicKeyInfoEx failed: %08lx\n", GetLastError());
-        *pInfo = HeapAlloc(GetProcessHeap(), 0, size);
+        *pInfo = malloc(size);
          if (*pInfo)
          {
               ret = CryptExportPublicKeyInfoEx(csp, AT_SIGNATURE,
@@ -8411,7 +8410,7 @@ static void testPortPublicKeyInfo(void)
     testExportPublicKey(csp, &info);
     testImportPublicKey(csp, info);

-    HeapFree(GetProcessHeap(), 0, info);
+    free(info);
     CryptReleaseContext(csp, 0);
     ret = CryptAcquireContextA(&csp, cspName, MS_DEF_PROV_A, PROV_RSA_FULL,
     CRYPT_DELETEKEYSET);
@@ -8674,6 +8673,26 @@ static const BYTE ocsp_basic_response[] = {
     0x33, 0x36, 0x30, 0x31, 0x5a
};

+static const BYTE ocsp_basic_response2[] = {
+  0x30, 0x81, 0xbe, 0xa1, 0x34, 0x30, 0x32, 0x31, 0x0b, 0x30, 0x09, 0x06,
+  0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x16, 0x30, 0x14,
+  0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0d, 0x4c, 0x65, 0x74, 0x27, 0x73,
+  0x20, 0x45, 0x6e, 0x63, 0x72, 0x79, 0x70, 0x74, 0x31, 0x0b, 0x30, 0x09,
+  0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x02, 0x52, 0x33, 0x18, 0x0f, 0x32,
+  0x30, 0x32, 0x32, 0x31, 0x30, 0x32, 0x30, 0x30, 0x36, 0x30, 0x31, 0x30,
+  0x30, 0x5a, 0x30, 0x75, 0x30, 0x73, 0x30, 0x4b, 0x30, 0x09, 0x06, 0x05,
+  0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14, 0x48, 0xda, 0xc9,
+  0xa0, 0xfb, 0x2b, 0xd3, 0x2d, 0x4f, 0xf0, 0xde, 0x68, 0xd2, 0xf5, 0x67,
+  0xb7, 0x35, 0xf9, 0xb3, 0xc4, 0x04, 0x14, 0x14, 0x2e, 0xb3, 0x17, 0xb7,
+  0x58, 0x56, 0xcb, 0xae, 0x50, 0x09, 0x40, 0xe6, 0x1f, 0xaf, 0x9d, 0x8b,
+  0x14, 0xc2, 0xc6, 0x02, 0x12, 0x03, 0x26, 0x1c, 0x82, 0x80, 0xf3, 0x8c,
+  0x13, 0xef, 0xae, 0x83, 0x9d, 0x89, 0xb9, 0xcd, 0x59, 0x83, 0x5b, 0x80,
+  0x00, 0x18, 0x0f, 0x32, 0x30, 0x32, 0x32, 0x31, 0x30, 0x32, 0x30, 0x30,
+  0x36, 0x30, 0x30, 0x30, 0x30, 0x5a, 0xa0, 0x11, 0x18, 0x0f, 0x32, 0x30,
+  0x32, 0x32, 0x31, 0x30, 0x32, 0x37, 0x30, 0x35, 0x35, 0x39, 0x35, 0x38,
+  0x5a
+};
static const BYTE ocsp_basic_response_revoked[] = {
     0x30, 0x81, 0xb1, 0xa2, 0x16, 0x04, 0x14, 0xa4, 0x8d, 0xe5, 0xbe, 0x7c,
     0x79, 0xe4, 0x70, 0x23, 0x6d, 0x2e, 0x29, 0x34, 0xad, 0x23, 0x58, 0xdc,
@@ -8759,22 +8778,36 @@ static void test_decodeOCSPBasicResponseInfo(DWORD dwEncoding)
     static const BYTE resp_id2[] = {
          0xa4, 0x8d, 0xe5, 0xbe, 0x7c, 0x79, 0xe4, 0x70, 0x23, 0x6d, 0x2e, 0x29, 0x34, 0xad, 0x23, 0x58,
          0xdc, 0xf5, 0x31, 0x7f};
+    static const BYTE resp_id3[] = {
+        0x30, 0x32, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31,
+        0x16, 0x30, 0x14, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0d, 0x4c, 0x65, 0x74, 0x27, 0x73, 0x20,
+        0x45, 0x6e, 0x63, 0x72, 0x79, 0x70, 0x74, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x03,
+        0x13, 0x02, 0x52, 0x33};
     static const BYTE name_hash[] = {
          0xe4, 0xe3, 0x95, 0xa2, 0x29, 0xd3, 0xd4, 0xc1, 0xc3, 0x1f, 0xf0, 0x98, 0x0c, 0x0b, 0x4e, 0xc0,
          0x09, 0x8a, 0xab, 0xd8};
     static const BYTE name_hash2[] = {
          0x74, 0xb4, 0xe7, 0x23, 0x19, 0xc7, 0x65, 0x92, 0x15, 0x40, 0x44, 0x7b, 0xc7, 0xce, 0x3e, 0x90,
          0xc2, 0x18, 0x76, 0xeb};
+    static const BYTE name_hash3[] = {
+        0x48, 0xda, 0xc9, 0xa0, 0xfb, 0x2b, 0xd3, 0x2d, 0x4f, 0xf0, 0xde, 0x68, 0xd2, 0xf5, 0x67, 0xb7,
+        0x35, 0xf9, 0xb3, 0xc4};
     static const BYTE key_hash[] = {
          0xb7, 0x6b, 0xa2, 0xea, 0xa8, 0xaa, 0x84, 0x8c, 0x79, 0xea, 0xb4, 0xda, 0x0f, 0x98, 0xb2, 0xc5,
          0x95, 0x76, 0xb9, 0xf4};
     static const BYTE key_hash2[] = {
          0xa4, 0x8d, 0xe5, 0xbe, 0x7c, 0x79, 0xe4, 0x70, 0x23, 0x6d, 0x2e, 0x29, 0x34, 0xad, 0x23, 0x58,
          0xdc, 0xf5, 0x31, 0x7f};
+    static const BYTE key_hash3[] = {
+        0x14, 0x2e, 0xb3, 0x17, 0xb7, 0x58, 0x56, 0xcb, 0xae, 0x50, 0x09, 0x40, 0xe6, 0x1f, 0xaf, 0x9d,
+        0x8b, 0x14, 0xc2, 0xc6};
     static const BYTE serial[] = {
          0xb1, 0xc1, 0x87, 0x54, 0x54, 0xac, 0x1e, 0x55, 0x40, 0xfb, 0xef, 0xd9, 0x6d, 0x8f, 0x49, 0x08};
     static const BYTE serial2[] = {
          0x2f, 0x57, 0xa4, 0x85, 0xa2, 0xe3, 0x52, 0x54, 0x9a, 0x3b, 0x85, 0x98, 0xa2, 0x67, 0x2e, 0x0d};
+    static const BYTE serial3[] = {
+        0x5b, 0x83, 0x59, 0xcd, 0xb9, 0x89, 0x9d, 0x83, 0xae, 0xef, 0x13, 0x8c, 0xf3, 0x80, 0x82, 0x1c,
+        0x26, 0x03};
     OCSP_BASIC_RESPONSE_INFO *info;
     OCSP_BASIC_RESPONSE_ENTRY *entry;
     OCSP_BASIC_REVOKED_INFO *revoked;
@@ -8801,11 +8834,11 @@ static void test_decodeOCSPBasicResponseInfo(DWORD dwEncoding)
     ok(entry->CertId.HashAlgorithm.Parameters.cbData == 2, "got %lu\n", entry->CertId.HashAlgorithm.Parameters.cbData);
     ok(entry->CertId.HashAlgorithm.Parameters.pbData[0] == 5, "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[0]);
     ok(!entry->CertId.HashAlgorithm.Parameters.pbData[1], "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[1]);
-    ok(entry->CertId.IssuerNameHash.cbData == 20, "got %lu\n", entry->CertId.IssuerNameHash.cbData);
+    ok(entry->CertId.IssuerNameHash.cbData == sizeof(name_hash), "got %lu\n", entry->CertId.IssuerNameHash.cbData);
     ok(!memcmp(entry->CertId.IssuerNameHash.pbData, name_hash, sizeof(name_hash)), "wrong data\n");
-    ok(entry->CertId.IssuerKeyHash.cbData == 20, "got %lu\n", entry->CertId.IssuerKeyHash.cbData);
+    ok(entry->CertId.IssuerKeyHash.cbData == sizeof(key_hash), "got %lu\n", entry->CertId.IssuerKeyHash.cbData);
     ok(!memcmp(entry->CertId.IssuerKeyHash.pbData, key_hash, sizeof(key_hash)), "wrong data\n");
-    ok(entry->CertId.SerialNumber.cbData == 16, "got %lu\n", entry->CertId.SerialNumber.cbData);
+    ok(entry->CertId.SerialNumber.cbData == sizeof(serial), "got %lu\n", entry->CertId.SerialNumber.cbData);
     ok(!memcmp(entry->CertId.SerialNumber.pbData, serial, sizeof(serial)), "wrong data\n");
     ok(entry->dwCertStatus == 0, "got %lu\n", entry->dwCertStatus);
     ok(entry->pRevokedInfo == NULL, "got %p\n", entry->pRevokedInfo);
@@ -8824,9 +8857,8 @@ static void test_decodeOCSPBasicResponseInfo(DWORD dwEncoding)
     size = 0;
     ret = CryptDecodeObjectEx(dwEncoding, OCSP_BASIC_RESPONSE, ocsp_basic_response_revoked,
                              sizeof(ocsp_basic_response_revoked), CRYPT_DECODE_ALLOC_FLAG, NULL, &info, &size);
-    todo_wine ok(ret, "got %08lx\n", GetLastError());
+    ok(ret, "got %08lx\n", GetLastError());

-    if (ret) {
     ok(!info->dwVersion, "got %lu\n", info->dwVersion);
     ok(info->dwResponderIdChoice == 2, "got %lu\n", info->dwResponderIdChoice);
     ok(info->ByKeyResponderId.cbData == sizeof(resp_id), "got %lu\n", info->ByKeyResponderId.cbData);
@@ -8841,11 +8873,11 @@ static void test_decodeOCSPBasicResponseInfo(DWORD dwEncoding)
     ok(entry->CertId.HashAlgorithm.Parameters.cbData == 2, "got %lu\n", entry->CertId.HashAlgorithm.Parameters.cbData);
     ok(entry->CertId.HashAlgorithm.Parameters.pbData[0] == 5, "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[0]);
     ok(!entry->CertId.HashAlgorithm.Parameters.pbData[1], "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[1]);
-    ok(entry->CertId.IssuerNameHash.cbData == 20, "got %lu\n", entry->CertId.IssuerNameHash.cbData);
+    ok(entry->CertId.IssuerNameHash.cbData == sizeof(name_hash2), "got %lu\n", entry->CertId.IssuerNameHash.cbData);
     ok(!memcmp(entry->CertId.IssuerNameHash.pbData, name_hash2, sizeof(name_hash2)), "wrong data\n");
-    ok(entry->CertId.IssuerKeyHash.cbData == 20, "got %lu\n", entry->CertId.IssuerKeyHash.cbData);
+    ok(entry->CertId.IssuerKeyHash.cbData == sizeof(key_hash2), "got %lu\n", entry->CertId.IssuerKeyHash.cbData);
     ok(!memcmp(entry->CertId.IssuerKeyHash.pbData, key_hash2, sizeof(key_hash2)), "wrong data\n");
-    ok(entry->CertId.SerialNumber.cbData == 16, "got %lu\n", entry->CertId.SerialNumber.cbData);
+    ok(entry->CertId.SerialNumber.cbData == sizeof(serial2), "got %lu\n", entry->CertId.SerialNumber.cbData);
     ok(!memcmp(entry->CertId.SerialNumber.pbData, serial2, sizeof(serial2)), "wrong data\n");
     ok(entry->dwCertStatus == 1, "got %lu\n", entry->dwCertStatus);
     ok(entry->pRevokedInfo != NULL, "got NULL\n");
@@ -8864,7 +8896,46 @@ static void test_decodeOCSPBasicResponseInfo(DWORD dwEncoding)

     ok(!info->cExtension, "got %lu\n", info->cExtension);
     ok(info->rgExtension == NULL, "got %p\n", info->rgExtension);
-    }
+    LocalFree(info);
+    size = 0;
+    ret = CryptDecodeObjectEx(dwEncoding, OCSP_BASIC_RESPONSE, ocsp_basic_response2,
+                              sizeof(ocsp_basic_response2), CRYPT_DECODE_ALLOC_FLAG, NULL, &info, &size);
+    ok(ret, "got %08lx\n", GetLastError());
+    ok(!info->dwVersion, "got %lu\n", info->dwVersion);
+    ok(info->dwResponderIdChoice == 1, "got %lu\n", info->dwResponderIdChoice);
+    ok(info->ByNameResponderId.cbData == sizeof(resp_id3), "got %lu\n", info->ByNameResponderId.cbData);
+    ok(!memcmp(info->ByNameResponderId.pbData, resp_id3, sizeof(resp_id3)), "wrong data\n");
+    ok(info->ProducedAt.dwLowDateTime == 1408824832, "got %lu\n", info->ProducedAt.dwLowDateTime);
+    ok(info->ProducedAt.dwHighDateTime == 30991433, "got %lu\n", info->ProducedAt.dwHighDateTime);
+    ok(info->cResponseEntry == 1, "got %lu\n", info->cResponseEntry);
+    ok(info->rgResponseEntry != NULL, "got %p\n", info->rgResponseEntry);
+    entry = info->rgResponseEntry;
+    ok(!strcmp(entry->CertId.HashAlgorithm.pszObjId, szOID_OIWSEC_sha1), "got '%s'\n", entry->CertId.HashAlgorithm.pszObjId);
+    ok(entry->CertId.HashAlgorithm.Parameters.cbData == 2, "got %lu\n", entry->CertId.HashAlgorithm.Parameters.cbData);
+    ok(entry->CertId.HashAlgorithm.Parameters.pbData[0] == 5, "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[0]);
+    ok(!entry->CertId.HashAlgorithm.Parameters.pbData[1], "got 0x%02x\n", entry->CertId.HashAlgorithm.Parameters.pbData[1]);
+    ok(entry->CertId.IssuerNameHash.cbData == sizeof(name_hash3), "got %lu\n", entry->CertId.IssuerNameHash.cbData);
+    ok(!memcmp(entry->CertId.IssuerNameHash.pbData, name_hash3, sizeof(name_hash3)), "wrong data\n");
+    ok(entry->CertId.IssuerKeyHash.cbData == sizeof(key_hash3), "got %lu\n", entry->CertId.IssuerKeyHash.cbData);
+    ok(!memcmp(entry->CertId.IssuerKeyHash.pbData, key_hash3, sizeof(key_hash3)), "wrong data\n");
+    ok(entry->CertId.SerialNumber.cbData == sizeof(serial3), "got %lu\n", entry->CertId.SerialNumber.cbData);
+    ok(!memcmp(entry->CertId.SerialNumber.pbData, serial3, sizeof(serial3)), "wrong data\n");
+    ok(entry->dwCertStatus == 0, "got %lu\n", entry->dwCertStatus);
+    ok(entry->pRevokedInfo == NULL, "got %p\n", entry->pRevokedInfo);
+    ok(entry->ThisUpdate.dwLowDateTime == 808824832, "got %lu\n", entry->ThisUpdate.dwLowDateTime);
+    ok(entry->ThisUpdate.dwHighDateTime == 30991433, "got %lu\n", entry->ThisUpdate.dwHighDateTime);
+    ok(entry->NextUpdate.dwLowDateTime == 1474872064, "got %lu\n", entry->NextUpdate.dwLowDateTime);
+    ok(entry->NextUpdate.dwHighDateTime == 30992841, "got %lu\n", entry->NextUpdate.dwHighDateTime);
+    ok(!entry->cExtension, "got %lu\n", entry->cExtension);
+    ok(entry->rgExtension == NULL, "got %p\n", entry->rgExtension);
+    ok(!info->cExtension, "got %lu\n", info->cExtension);
+    ok(info->rgExtension == NULL, "got %p\n", info->rgExtension);
     LocalFree(info);
}

diff --git a/wine/dlls/crypt32/tests/main.c b/wine/dlls/crypt32/tests/main.c
index 19dde3fb2..1b125e89d 100644
--- a/wine/dlls/crypt32/tests/main.c
+++ b/wine/dlls/crypt32/tests/main.c
@@ -349,7 +349,7 @@ static void test_getDefaultCryptProv(void)
          prov = pI_CryptGetDefaultCryptProv(test_prov[i].algid);
          if (!prov)
          {
-            todo_wine_if(test_prov[i].algid == CALG_DSS_SIGN || test_prov[i].algid == CALG_NO_SIGN)
+todo_wine_if(test_prov[i].algid == CALG_DSS_SIGN || test_prov[i].algid == CALG_NO_SIGN)
               ok(test_prov[i].optional, "%lu: I_CryptGetDefaultCryptProv(%#x) failed\n", i, test_prov[i].algid);
               continue;
          }
diff --git a/wine/dlls/crypt32/tests/message.c b/wine/dlls/crypt32/tests/message.c
index fa4790a2a..e6339553e 100644
--- a/wine/dlls/crypt32/tests/message.c
+++ b/wine/dlls/crypt32/tests/message.c
@@ -688,14 +688,14 @@ static void test_hash_message(void)
          /* Actually attempting to get the hashed data fails, perhaps because
          * detached is FALSE.
          */
-        hashedBlob = HeapAlloc(GetProcessHeap(), 0, hashedBlobSize);
+        hashedBlob = malloc(hashedBlobSize);
          SetLastError(0xdeadbeef);
          ret = CryptHashMessage(&para, FALSE, 2, toHash, hashSize, hashedBlob,
          &hashedBlobSize, NULL, NULL);
          ok(!ret && GetLastError() == CRYPT_E_MSG_ERROR,
          "expected CRYPT_E_MSG_ERROR, got 0x%08lx (%ld)\n", GetLastError(),
          GetLastError());
-        HeapFree(GetProcessHeap(), 0, hashedBlob);
+        free(hashedBlob);
     }
     /* Repeating tests with fDetached = TRUE results in success */
     SetLastError(0xdeadbeef);
@@ -704,7 +704,7 @@ static void test_hash_message(void)
     ok(ret, "CryptHashMessage failed: 0x%08lx\n", GetLastError());
     if (ret)
     {
-        hashedBlob = HeapAlloc(GetProcessHeap(), 0, hashedBlobSize);
+        hashedBlob = malloc(hashedBlobSize);
          SetLastError(0xdeadbeef);
          ret = CryptHashMessage(&para, TRUE, 2, toHash, hashSize, hashedBlob,
          &hashedBlobSize, NULL, NULL);
@@ -713,7 +713,7 @@ static void test_hash_message(void)
          "unexpected size of detached blob %ld\n", hashedBlobSize);
          ok(!memcmp(hashedBlob, detachedHashBlob, hashedBlobSize),
          "unexpected detached blob value\n");
-        HeapFree(GetProcessHeap(), 0, hashedBlob);
+        free(hashedBlob);
     }
     /* Hashing a single item with fDetached = FALSE also succeeds */
     SetLastError(0xdeadbeef);
@@ -722,7 +722,7 @@ static void test_hash_message(void)
     ok(ret, "CryptHashMessage failed: 0x%08lx\n", GetLastError());
     if (ret)
     {
-        hashedBlob = HeapAlloc(GetProcessHeap(), 0, hashedBlobSize);
+        hashedBlob = malloc(hashedBlobSize);
          ret = CryptHashMessage(&para, FALSE, 1, toHash, hashSize, hashedBlob,
          &hashedBlobSize, NULL, NULL);
          ok(ret, "CryptHashMessage failed: 0x%08lx\n", GetLastError());
@@ -730,7 +730,7 @@ static void test_hash_message(void)
          "unexpected size of detached blob %ld\n", hashedBlobSize);
          ok(!memcmp(hashedBlob, hashBlob, hashedBlobSize),
          "unexpected detached blob value\n");
-        HeapFree(GetProcessHeap(), 0, hashedBlob);
+        free(hashedBlob);
     }
     /* Check the computed hash value too.  You don't need to get the encoded
     * blob to get it.
@@ -743,7 +743,7 @@ static void test_hash_message(void)
     computedHashSize);
     if (ret)
     {
-        computedHash = HeapAlloc(GetProcessHeap(), 0, computedHashSize);
+        computedHash = malloc(computedHashSize);
          SetLastError(0xdeadbeef);
          ret = CryptHashMessage(&para, TRUE, 2, toHash, hashSize, NULL,
          &hashedBlobSize, computedHash, &computedHashSize);
@@ -752,7 +752,7 @@ static void test_hash_message(void)
          "unexpected size of hash value %ld\n", computedHashSize);
          ok(!memcmp(computedHash, hashVal, computedHashSize),
          "unexpected value\n");
-        HeapFree(GetProcessHeap(), 0, computedHash);
+        free(computedHash);
     }
}

diff --git a/wine/dlls/crypt32/tests/msg.c b/wine/dlls/crypt32/tests/msg.c
index f779d7069..16f7402c6 100644
--- a/wine/dlls/crypt32/tests/msg.c
+++ b/wine/dlls/crypt32/tests/msg.c
@@ -274,14 +274,14 @@ static void check_param(LPCSTR test, HCRYPTMSG msg, DWORD param,
     ret = CryptMsgGetParam(msg, param, 0, NULL, &size);
     ok(ret, "%s: CryptMsgGetParam failed: %08lx\n", test, GetLastError());

-    buf = HeapAlloc(GetProcessHeap(), 0, size);
+    buf = malloc(size);
     ret = CryptMsgGetParam(msg, param, 0, buf, &size);
     ok(ret, "%s: CryptMsgGetParam failed: %08lx\n", test, GetLastError());
     ok(size == expectedSize, "%s: expected size %ld, got %ld\n", test,
     expectedSize, size);
     if (size == expectedSize && size)
          ok(!memcmp(buf, expected, size), "%s: unexpected data\n", test);
-    HeapFree(GetProcessHeap(), 0, buf);
+    free(buf);
}

static void test_data_msg_open(void)
diff --git a/wine/dlls/crypt32/tests/object.c b/wine/dlls/crypt32/tests/object.c
index 22936d373..a3c7c8c07 100644
--- a/wine/dlls/crypt32/tests/object.c
+++ b/wine/dlls/crypt32/tests/object.c
@@ -95,130 +95,10 @@ L"MIIBiQYJKoZIhvcNAQcCoIIBejCCAXYCAQExDjAMBggqhkiG9w0CBQUAMBMGCSqG"
"s+9Z0WbRm8CatppebW9tDVmpqm7pLKAe7sJgvFm+P2MGjckRHSNkku8u/FcppK/g"
"7pMZOVHkRLgLKPSoDQ==";

-/* Self-signed .exe, built with tcc, signed with signtool
- * (and a certificate generated on a self-signed CA).
- *
- * small.c:
- * int _start()
- * {
- *     return 0;
- * }
- *
- * tcc -nostdlib small.c
- * signtool sign /v /f codesign.pfx small.exe
- */
-static const BYTE signed_pe_blob[] =
-{
-    0x4D,0x5A,0x90,0x00,0x03,0x00,0x00,0x00,0x04,0x00,0x00,0x00,0xFF,0xFF,0x00,0x00,0xB8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x40,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x80,0x00,0x00,0x00,0x0E,0x1F,0xBA,0x0E,0x00,0xB4,0x09,0xCD,
-    0x21,0xB8,0x01,0x4C,0xCD,0x21,0x54,0x68,0x69,0x73,0x20,0x70,0x72,0x6F,0x67,0x72,0x61,0x6D,0x20,0x63,0x61,0x6E,0x6E,0x6F,
-    0x74,0x20,0x62,0x65,0x20,0x72,0x75,0x6E,0x20,0x69,0x6E,0x20,0x44,0x4F,0x53,0x20,0x6D,0x6F,0x64,0x65,0x2E,0x0D,0x0D,0x0A,
-    0x24,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x50,0x45,0x00,0x00,0x4C,0x01,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0xE0,0x00,0x0F,0x03,0x0B,0x01,0x06,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x10,0x00,0x00,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x40,0x00,0x00,0x10,0x00,0x00,0x00,0x02,0x00,0x00,
-    0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x02,0x00,0x00,
-    0xE7,0x0C,0x00,0x00,0x03,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x68,0x05,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x2E,0x74,0x65,0x78,0x74,0x00,0x00,0x00,
-    0x18,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x20,0x00,0x00,0x60,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x55,0x89,0xE5,0x81,0xEC,0x00,0x00,0x00,0x00,0x90,0xB8,0x00,0x00,0x00,0x00,0xE9,
-    0x00,0x00,0x00,0x00,0xC9,0xC3,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
-    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x68,0x05,0x00,0x00,0x00,0x02,0x02,0x00,
-    /* Start of the signature overlay */
-    0x30,0x82,0x05,0x5A,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x07,0x02,0xA0,0x82,0x05,0x4B,0x30,0x82,0x05,0x47,0x02,
-    0x01,0x01,0x31,0x0B,0x30,0x09,0x06,0x05,0x2B,0x0E,0x03,0x02,0x1A,0x05,0x00,0x30,0x4C,0x06,0x0A,0x2B,0x06,0x01,0x04,0x01,
-    0x82,0x37,0x02,0x01,0x04,0xA0,0x3E,0x30,0x3C,0x30,0x17,0x06,0x0A,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x02,0x01,0x0F,0x30,
-    0x09,0x03,0x01,0x00,0xA0,0x04,0xA2,0x02,0x80,0x00,0x30,0x21,0x30,0x09,0x06,0x05,0x2B,0x0E,0x03,0x02,0x1A,0x05,0x00,0x04,
-    0x14,0xA0,0x95,0xDE,0xBD,0x1A,0xB7,0x86,0xAF,0x50,0x63,0xD8,0x8F,0x90,0xD5,0x49,0x96,0x4E,0x44,0xF0,0x71,0xA0,0x82,0x03,
-    0x1D,0x30,0x82,0x03,0x19,0x30,0x82,0x02,0x01,0xA0,0x03,0x02,0x01,0x02,0x02,0x10,0x96,0x53,0x2C,0xC9,0x23,0x56,0x8A,0x87,
-    0x42,0x30,0x3E,0xD5,0x8D,0x72,0xD5,0x25,0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x0B,0x05,0x00,0x30,
-    0x17,0x31,0x15,0x30,0x13,0x06,0x03,0x55,0x04,0x03,0x13,0x0C,0x54,0x65,0x73,0x74,0x20,0x43,0x41,0x20,0x52,0x6F,0x6F,0x74,
-    0x30,0x1E,0x17,0x0D,0x31,0x36,0x30,0x33,0x30,0x33,0x32,0x30,0x32,0x37,0x30,0x37,0x5A,0x17,0x0D,0x34,0x39,0x31,0x32,0x33,
-    0x31,0x32,0x33,0x30,0x30,0x30,0x30,0x5A,0x30,0x17,0x31,0x15,0x30,0x13,0x06,0x03,0x55,0x04,0x03,0x13,0x0C,0x43,0x6F,0x64,
-    0x65,0x53,0x69,0x67,0x6E,0x54,0x65,0x73,0x74,0x30,0x82,0x01,0x22,0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,
-    0x01,0x01,0x05,0x00,0x03,0x82,0x01,0x0F,0x00,0x30,0x82,0x01,0x0A,0x02,0x82,0x01,0x01,0x00,0xB2,0xC9,0x91,0x98,0x8C,0xDC,
-    0x80,0xBC,0x16,0xBF,0xC1,0x04,0x77,0x90,0xC0,0xFD,0x8C,0xBA,0x68,0x26,0xAC,0xB7,0x20,0x68,0x41,0xED,0xC3,0x9C,0x47,0x7C,
-    0x36,0xC2,0x7B,0xE1,0x5E,0xFD,0xA9,0x99,0xF4,0x29,0x36,0x86,0x93,0x40,0x55,0x53,0x65,0x79,0xBC,0x9F,0x8F,0x6E,0x2B,0x05,
-    0x84,0xE1,0xFD,0xD2,0xEF,0xEA,0x89,0x8C,0xEC,0xF9,0x55,0xF0,0x2C,0xE5,0xA7,0x29,0xF9,0x7E,0x50,0xDC,0x9C,0xA1,0x23,0xA5,
-    0xD9,0x78,0xA1,0xE7,0x7C,0xD7,0x04,0x4F,0x11,0xAC,0x9F,0x4A,0x47,0xA1,0x1E,0xD5,0x9E,0xE7,0x5B,0xB5,0x8C,0x9C,0x67,0x7A,
-    0xD0,0xF8,0x54,0xD1,0x64,0x7F,0x39,0x48,0xB6,0xCF,0x2F,0x26,0x7D,0x7B,0x13,0x2B,0xC2,0x8F,0xA6,0x3F,0x42,0x71,0x95,0x3E,
-    0x59,0x0F,0x12,0xFA,0xC2,0x70,0x89,0xB7,0xB6,0x10,0x49,0xE0,0x7D,0x4D,0xFC,0x80,0x61,0x53,0x50,0x72,0xFD,0x46,0x35,0x51,
-    0x36,0xE6,0x06,0xA9,0x4C,0x0D,0x82,0x15,0xF6,0x5D,0xDE,0xD4,0xDB,0xE7,0x82,0x10,0x40,0xA1,0x47,0x68,0x88,0x0C,0x0A,0x80,
-    0xD1,0xE5,0x9A,0x35,0x28,0x82,0x1F,0x0F,0x80,0x5A,0x6E,0x1D,0x22,0x22,0xB3,0xA7,0xA2,0x9E,0x82,0x2D,0xC0,0x7F,0x5A,0xD0,
-    0xBA,0xB2,0xCA,0x20,0xE2,0x97,0xE9,0x72,0x41,0xB7,0xD6,0x1A,0x93,0x23,0x97,0xF0,0xA9,0x61,0xD2,0x91,0xBD,0xB6,0x6B,0x95,
-    0x12,0x67,0x16,0xAC,0x0A,0xB7,0x55,0x02,0x0D,0xA5,0xAD,0x17,0x95,0x77,0xF9,0x96,0x03,0x41,0xD3,0xE1,0x61,0x68,0xBB,0x0A,
-    0xB5,0xC4,0xEE,0x70,0x40,0x08,0x05,0xC4,0xF1,0x5D,0x02,0x03,0x01,0x00,0x01,0xA3,0x61,0x30,0x5F,0x30,0x13,0x06,0x03,0x55,
-    0x1D,0x25,0x04,0x0C,0x30,0x0A,0x06,0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x03,0x30,0x48,0x06,0x03,0x55,0x1D,0x01,0x04,
-    0x41,0x30,0x3F,0x80,0x10,0x35,0x40,0x67,0x8F,0x7D,0x03,0x1B,0x76,0x52,0x62,0x2D,0xF5,0x21,0xF6,0x7C,0xBC,0xA1,0x19,0x30,
-    0x17,0x31,0x15,0x30,0x13,0x06,0x03,0x55,0x04,0x03,0x13,0x0C,0x54,0x65,0x73,0x74,0x20,0x43,0x41,0x20,0x52,0x6F,0x6F,0x74,
-    0x82,0x10,0xA0,0x4B,0xEB,0xAC,0xFA,0x08,0xF2,0x8B,0x47,0xD2,0xB3,0x54,0x60,0x6C,0xE6,0x29,0x30,0x0D,0x06,0x09,0x2A,0x86,
-    0x48,0x86,0xF7,0x0D,0x01,0x01,0x0B,0x05,0x00,0x03,0x82,0x01,0x01,0x00,0x5F,0x8C,0x7F,0xDA,0x1D,0x21,0x7A,0x15,0xD8,0x20,
-    0x04,0x53,0x7F,0x44,0x6D,0x7B,0x57,0xBE,0x7F,0x86,0x77,0x58,0xC4,0xD4,0x80,0xC7,0x2E,0x64,0x9B,0x44,0xC5,0x2D,0x6D,0xDB,
-    0x35,0x5A,0xFE,0xA4,0xD8,0x66,0x9B,0xF7,0x6E,0xFC,0xEF,0x52,0x7B,0xC5,0x16,0xE6,0xA3,0x7D,0x59,0xB7,0x31,0x28,0xEB,0xB5,
-    0x45,0xC9,0xB1,0xD1,0x08,0x67,0xC6,0x37,0xE7,0xD7,0x2A,0xE6,0x1F,0xD9,0x6A,0xE5,0x04,0xDF,0x6A,0x9D,0x91,0xFA,0x41,0xBD,
-    0x2A,0x50,0xEA,0x99,0x24,0xA9,0x0F,0x2B,0x50,0x51,0x5F,0xD9,0x0B,0x89,0x1B,0xCB,0xDB,0x88,0xE8,0xEC,0x87,0xB0,0x16,0xCC,
-    0x43,0xEE,0x5A,0xBD,0x57,0xE2,0x46,0xA7,0x56,0x54,0x23,0x32,0x8A,0xFB,0x25,0x51,0x39,0x38,0xE6,0x87,0xF5,0x73,0x63,0xD0,
-    0x5B,0xC7,0x3F,0xFD,0x04,0x75,0x74,0x4C,0x3D,0xB5,0x31,0x22,0x7D,0xF1,0x8D,0xB4,0xE0,0xAA,0xE1,0xFF,0x8F,0xDD,0xB8,0x04,
-    0x6A,0x31,0xEE,0x30,0x2D,0x6E,0x74,0x0F,0x37,0x71,0x77,0x2B,0xB8,0x9E,0x62,0x47,0x00,0x9C,0xA5,0x82,0x2B,0x9F,0x24,0x67,
-    0x50,0x86,0x8B,0xC9,0x36,0x81,0xEB,0x44,0xC2,0xF1,0x91,0xA6,0x84,0x75,0x15,0x8F,0x22,0xDE,0xAC,0xB5,0x16,0xE3,0x96,0x74,
-    0x72,0x2F,0x15,0xD5,0xFB,0x01,0x22,0xC4,0x24,0xEE,0x3D,0xDF,0x9E,0xA9,0x0A,0x5B,0x16,0x21,0xE8,0x4A,0x8C,0x7E,0x3A,0x9C,
-    0x22,0xA0,0x49,0x60,0x97,0x1B,0x3E,0x2D,0x80,0x91,0xDB,0xF7,0x78,0x38,0x76,0x78,0x0C,0xE3,0xD4,0x27,0x77,0x69,0x96,0xE6,
-    0x41,0xC7,0x2E,0xE9,0x61,0xD6,0x31,0x82,0x01,0xC4,0x30,0x82,0x01,0xC0,0x02,0x01,0x01,0x30,0x2B,0x30,0x17,0x31,0x15,0x30,
-    0x13,0x06,0x03,0x55,0x04,0x03,0x13,0x0C,0x54,0x65,0x73,0x74,0x20,0x43,0x41,0x20,0x52,0x6F,0x6F,0x74,0x02,0x10,0x96,0x53,
-    0x2C,0xC9,0x23,0x56,0x8A,0x87,0x42,0x30,0x3E,0xD5,0x8D,0x72,0xD5,0x25,0x30,0x09,0x06,0x05,0x2B,0x0E,0x03,0x02,0x1A,0x05,
-    0x00,0xA0,0x70,0x30,0x10,0x06,0x0A,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x02,0x01,0x0C,0x31,0x02,0x30,0x00,0x30,0x19,0x06,
-    0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x09,0x03,0x31,0x0C,0x06,0x0A,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x02,0x01,0x04,
-    0x30,0x1C,0x06,0x0A,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x02,0x01,0x0B,0x31,0x0E,0x30,0x0C,0x06,0x0A,0x2B,0x06,0x01,0x04,
-    0x01,0x82,0x37,0x02,0x01,0x15,0x30,0x23,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x09,0x04,0x31,0x16,0x04,0x14,0x3D,
-    0x08,0xC8,0xA3,0xEE,0x05,0x1A,0x61,0xD9,0xFE,0x1A,0x63,0xC0,0x8A,0x6E,0x9D,0xF9,0xC3,0x13,0x98,0x30,0x0D,0x06,0x09,0x2A,
-    0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x01,0x05,0x00,0x04,0x82,0x01,0x00,0x90,0xF9,0xC0,0x7F,0x1D,0x70,0x8C,0x04,0x22,0x82,
-    0xB6,0x2D,0x48,0xBF,0x30,0x51,0x29,0xF8,0xE3,0x11,0x39,0xE0,0x64,0x23,0x72,0xE2,0x4C,0x09,0x9F,0x39,0xF2,0x6F,0xDD,0xB9,
-    0x5A,0x3D,0xEF,0xEB,0xBE,0xEC,0x3B,0xE6,0x58,0x4C,0xC9,0x4F,0xED,0xCB,0x6E,0x9D,0x67,0x8E,0x89,0x92,0x40,0x39,0xA2,0x5F,
-    0xF9,0xEF,0xD3,0xF5,0x24,0x27,0x8D,0xF7,0x3C,0x92,0x66,0x56,0xC8,0x2B,0xEA,0x04,0xA1,0x0E,0xDA,0x89,0x30,0xA7,0x01,0xD8,
-    0x0B,0xF8,0xFD,0x99,0xB6,0xC0,0x38,0xB0,0x21,0x50,0x3A,0x86,0x01,0xD0,0xF3,0x86,0x72,0xE3,0x5A,0xBB,0x2A,0x6E,0xBD,0xFB,
-    0x22,0xF9,0x42,0xD3,0x04,0xFE,0x8D,0xD8,0x79,0xD1,0xEE,0x61,0xC6,0x48,0x04,0x99,0x9A,0xA2,0x73,0xE5,0xFB,0x24,0x10,0xD5,
-    0x6B,0x71,0x80,0x0E,0x09,0xEA,0x85,0x9A,0xBD,0xBB,0xDE,0x99,0x5D,0xA3,0x18,0x4D,0xED,0x20,0x73,0x3E,0x32,0xEF,0x2C,0xAC,
-    0x5A,0x83,0x87,0x1F,0x7F,0x19,0x61,0x35,0x53,0xC1,0xAA,0x89,0x97,0xB3,0xDD,0x8D,0xA8,0x67,0x5B,0xC2,0xE2,0x09,0xB7,0xDD,
-    0x6A,0xCB,0xD5,0xBF,0xD6,0x08,0xE2,0x23,0x1A,0x41,0x9D,0xD5,0x6A,0x6B,0x8D,0x3C,0x29,0x1B,0xF1,0x3F,0x4E,0x4A,0x8F,0x29,
-    0x33,0xF9,0x1C,0x60,0xA0,0x92,0x7E,0x4F,0x35,0xB8,0xDD,0xEB,0xD1,0x68,0x1A,0x9D,0xA2,0xA6,0x97,0x1F,0x5F,0xC6,0x2C,0xFB,
-    0xCA,0xDF,0xF7,0x95,0x33,0x95,0xD4,0x79,0x5C,0x73,0x87,0x49,0x1F,0x8C,0x6E,0xCE,0x3E,0x6D,0x3D,0x2B,0x6B,0xD7,0x66,0xE9,
-    0x88,0x6F,0xF2,0x83,0xB9,0x9B,0x00,0x00
-};
-
static void test_query_object(void)
{
-    WCHAR tmp_path[MAX_PATH];
     BOOL ret;
     CRYPT_DATA_BLOB blob;
-    DWORD content_type;

     /* Test the usual invalid arguments */
     SetLastError(0xdeadbeef);
@@ -308,26 +188,6 @@ static void test_query_object(void)
     CERT_QUERY_CONTENT_FLAG_ALL, CERT_QUERY_FORMAT_FLAG_BASE64_ENCODED, 0,
     NULL, NULL, NULL, NULL, NULL, NULL);
     ok(ret, "CryptQueryObject failed: %08lx\n", GetLastError());
-
-    GetEnvironmentVariableW( L"TMP", tmp_path, MAX_PATH );
-    SetEnvironmentVariableW(L"TMP", L"C:\\nonexistent");
-    blob.pbData = (BYTE *)signed_pe_blob;
-    blob.cbData = sizeof(signed_pe_blob);
-    ret = CryptQueryObject(CERT_QUERY_OBJECT_BLOB, &blob,
-        CERT_QUERY_CONTENT_FLAG_ALL, CERT_QUERY_FORMAT_FLAG_ALL, 0, NULL, &content_type,
-        NULL, NULL, NULL, NULL);
-    ok(!ret, "CryptQueryObject succeeded\n");
-    ok(GetLastError() == CRYPT_E_NO_MATCH, "Unexpected error %lu.\n", GetLastError());
-    SetEnvironmentVariableW(L"TMP", tmp_path);
-
-    blob.pbData = (BYTE *)signed_pe_blob;
-    blob.cbData = sizeof(signed_pe_blob);
-    ret = CryptQueryObject(CERT_QUERY_OBJECT_BLOB, &blob,
-        CERT_QUERY_CONTENT_FLAG_ALL, CERT_QUERY_FORMAT_FLAG_ALL, 0, NULL, &content_type,
-        NULL, NULL, NULL, NULL);
-    ok(ret, "CryptQueryObject failed: %08lx\n", GetLastError());
-    ok(content_type == CERT_QUERY_CONTENT_PKCS7_SIGNED_EMBED,
-            "Got unexpected content_type %#lx.\n", content_type);
}

START_TEST(object)
diff --git a/wine/dlls/crypt32/tests/oid.c b/wine/dlls/crypt32/tests/oid.c
index 9520e8c5a..715d76b9c 100644
--- a/wine/dlls/crypt32/tests/oid.c
+++ b/wine/dlls/crypt32/tests/oid.c
@@ -152,14 +152,14 @@ static void test_oidFunctionSet(void)
          ok(ret, "CryptGetDefaultOIDDllList failed: %08lx\n", GetLastError());
          if (ret)
          {
-            buf = HeapAlloc(GetProcessHeap(), 0, size * sizeof(WCHAR));
+            buf = malloc(size * sizeof(WCHAR));
               if (buf)
               {
               ret = CryptGetDefaultOIDDllList(set1, 0, buf, &size);
               ok(ret, "CryptGetDefaultOIDDllList failed: %08lx\n",
                    GetLastError());
               ok(!*buf, "Expected empty DLL list\n");
-                HeapFree(GetProcessHeap(), 0, buf);
+                free(buf);
               }
          }
     }
diff --git a/wine/dlls/crypt32/tests/store.c b/wine/dlls/crypt32/tests/store.c
index 00c2cae19..20d10a110 100644
--- a/wine/dlls/crypt32/tests/store.c
+++ b/wine/dlls/crypt32/tests/store.c
@@ -216,7 +216,7 @@ static void testMemStore(void)
          ret = CertSerializeCertificateStoreElement(context, 1, NULL, &size);
          ok(ret, "CertSerializeCertificateStoreElement failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertSerializeCertificateStoreElement(context, 0, buf, &size);
@@ -224,7 +224,7 @@ static void testMemStore(void)
               ok(size == sizeof(serializedCert), "Wrong size %ld\n", size);
               ok(!memcmp(serializedCert, buf, size),
               "Unexpected serialized cert\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }

          ret = CertFreeCertificateContext(context);
@@ -311,7 +311,7 @@ static void compareStore(HCERTSTORE store, LPCSTR name, const BYTE *pb,
     todo_wine_if (todo)
          ok(blob.cbData == cb, "%s: expected size %ld, got %ld\n", name, cb,
          blob.cbData);
-    blob.pbData = HeapAlloc(GetProcessHeap(), 0, blob.cbData);
+    blob.pbData = malloc(blob.cbData);
     if (blob.pbData)
     {
          ret = CertSaveStore(store, X509_ASN_ENCODING, CERT_STORE_SAVE_AS_STORE,
@@ -319,7 +319,7 @@ static void compareStore(HCERTSTORE store, LPCSTR name, const BYTE *pb,
          ok(ret, "CertSaveStore failed: %08lx\n", GetLastError());
          todo_wine_if (todo)
               ok(!memcmp(pb, blob.pbData, cb), "%s: unexpected value\n", name);
-        HeapFree(GetProcessHeap(), 0, blob.pbData);
+        free(blob.pbData);
     }
}

@@ -1063,7 +1063,7 @@ static void testRegStore(void)

               size = 0;
               RegQueryValueExA(subKey, "Blob", NULL, NULL, NULL, &size);
-            buf = HeapAlloc(GetProcessHeap(), 0, size);
+            buf = malloc(size);
               if (buf)
               {
               rc = RegQueryValueExA(subKey, "Blob", NULL, NULL, buf, &size);
@@ -1092,7 +1092,7 @@ static void testRegStore(void)
                         hdr->cb), "Unexpected hash in cert property\n");
                    }
               }
-                HeapFree(GetProcessHeap(), 0, buf);
+                free(buf);
               }
               RegCloseKey(subKey);
          }
@@ -2465,7 +2465,7 @@ static void testAddCertificateLink(void)
          ret = CertSerializeCertificateStoreElement(linked, 0, NULL, &size);
          ok(ret, "CertSerializeCertificateStoreElement failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertSerializeCertificateStoreElement(linked, 0, buf, &size);
@@ -2477,7 +2477,7 @@ static void testAddCertificateLink(void)
               ok(size == sizeof(serializedCert), "Wrong size %ld\n", size);
               ok(!memcmp(serializedCert, buf, size),
               "Unexpected serialized cert\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          /* Set a friendly name on the source certificate... */
          blob.pbData = (LPBYTE)L"WineTest";
@@ -2491,7 +2491,7 @@ static void testAddCertificateLink(void)
          CERT_FRIENDLY_NAME_PROP_ID, NULL, &size);
          ok(ret, "CertGetCertificateContextProperty failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertGetCertificateContextProperty(linked,
@@ -2500,7 +2500,7 @@ static void testAddCertificateLink(void)
               GetLastError());
               ok(!lstrcmpW((LPCWSTR)buf, L"WineTest"),
               "unexpected friendly name\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          CertFreeCertificateContext(linked);
     }
@@ -2541,7 +2541,7 @@ static void testAddCertificateLink(void)
          ret = CertSerializeCertificateStoreElement(linked, 0, NULL, &size);
          ok(ret, "CertSerializeCertificateStoreElement failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertSerializeCertificateStoreElement(linked, 0, buf, &size);
@@ -2552,7 +2552,7 @@ static void testAddCertificateLink(void)
               ok(size == sizeof(serializedCert), "Wrong size %ld\n", size);
               ok(!memcmp(serializedCert, buf, size),
               "Unexpected serialized cert\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          /* Set a friendly name on the source certificate... */
          blob.pbData = (LPBYTE)L"WineTest";
@@ -2566,7 +2566,7 @@ static void testAddCertificateLink(void)
          CERT_FRIENDLY_NAME_PROP_ID, NULL, &size);
          ok(ret, "CertGetCertificateContextProperty failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertGetCertificateContextProperty(linked,
@@ -2574,7 +2574,7 @@ static void testAddCertificateLink(void)
               ok(ret, "CertGetCertificateContextProperty failed: %08lx\n", GetLastError());
               ok(!lstrcmpW((LPCWSTR)buf, L"WineTest"),
               "unexpected friendly name\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          CertFreeCertificateContext(linked);
     }
@@ -2603,7 +2603,7 @@ static void testAddCertificateLink(void)
          ret = CertSerializeCertificateStoreElement(linked, 0, NULL, &size);
          ok(ret, "CertSerializeCertificateStoreElement failed: %08lx\n",
          GetLastError());
-        buf = HeapAlloc(GetProcessHeap(), 0, size);
+        buf = malloc(size);
          if (buf)
          {
               ret = CertSerializeCertificateStoreElement(linked, 0, buf, &size);
@@ -2616,7 +2616,7 @@ static void testAddCertificateLink(void)
               "Wrong size %ld\n", size);
               ok(!memcmp(serializedCertWithFriendlyName, buf, size),
               "Unexpected serialized cert\n");
-            HeapFree(GetProcessHeap(), 0, buf);
+            free(buf);
          }
          CertFreeCertificateContext(linked);
          compareStore(store2, "file store -> file store",
diff --git a/wine/dlls/crypt32/tests/str.c b/wine/dlls/crypt32/tests/str.c
index a94381591..5fb05bdb8 100644
--- a/wine/dlls/crypt32/tests/str.c
+++ b/wine/dlls/crypt32/tests/str.c
@@ -31,7 +31,6 @@ typedef struct _CertRDNAttrEncoding {
     DWORD  dwValueType;
     CERT_RDN_VALUE_BLOB Value;
     LPCSTR str;
-    BOOL todo;
} CertRDNAttrEncoding, *PCertRDNAttrEncoding;

typedef struct _CertRDNAttrEncodingW {
@@ -39,7 +38,6 @@ typedef struct _CertRDNAttrEncodingW {
     DWORD  dwValueType;
     CERT_RDN_VALUE_BLOB Value;
     LPCWSTR str;
-    BOOL todo;
} CertRDNAttrEncodingW, *PCertRDNAttrEncodingW;

static BYTE bin1[] = { 0x55, 0x53 };
@@ -115,6 +113,103 @@ static const BYTE cert[] =
0x65,0xd3,0xce,0xae,0x26,0x19,0x3,0x2e,0x4f,0x78,0xa5,0xa,0x97,0x7e,0x4f,0xc4,
0x91,0x8a,0xf8,0x5,0xef,0x5b,0x3b,0x49,0xbf,0x5f,0x2b};
+Certificate:
+    Data:
+        Version: 3 (0x2)
+        Serial Number:
+            5d:79:35:fd:d3:8f:6b:e2:28:3e:94:f4:14:bf:d4:b5:c2:3a:ac:38
+        Signature Algorithm: md5WithRSAEncryption
+        Issuer: C = US, ST = Minnesota, L = Minneapolis, O = CodeWeavers, CN = server_cn.org, emailAddress = test@codeweavers.com
+        Validity
+            Not Before: Apr 14 18:56:22 2022 GMT
+            Not After : Apr 11 18:56:22 2032 GMT
+        Subject: C = US, ST = Minnesota, L = Minneapolis, O = CodeWeavers, CN = server_cn.org, emailAddress = test@codeweavers.com
+        Subject Public Key Info:
+            Public Key Algorithm: rsaEncryption
+                RSA Public-Key: (1024 bit)
+                Modulus:
+...
+                Exponent: 65537 (0x10001)
+        X509v3 extensions:
+            X509v3 Subject Alternative Name:
+                DNS:ex1.org, DNS:*.ex2.org
+            X509v3 Issuer Alternative Name:
+                DNS:ex3.org, DNS:*.ex4.org
+    Signature Algorithm: md5WithRSAEncryption
+...
+*/
+static BYTE cert_v3[] = {
+    0x30, 0x82, 0x02, 0xdf, 0x30, 0x82, 0x02, 0x48, 0xa0, 0x03, 0x02, 0x01,
+    0x02, 0x02, 0x14, 0x5d, 0x79, 0x35, 0xfd, 0xd3, 0x8f, 0x6b, 0xe2, 0x28,
+    0x3e, 0x94, 0xf4, 0x14, 0xbf, 0xd4, 0xb5, 0xc2, 0x3a, 0xac, 0x38, 0x30,
+    0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x04,
+    0x05, 0x00, 0x30, 0x81, 0x8a, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55,
+    0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x12, 0x30, 0x10, 0x06, 0x03,
+    0x55, 0x04, 0x08, 0x0c, 0x09, 0x4d, 0x69, 0x6e, 0x6e, 0x65, 0x73, 0x6f,
+    0x74, 0x61, 0x31, 0x14, 0x30, 0x12, 0x06, 0x03, 0x55, 0x04, 0x07, 0x0c,
+    0x0b, 0x4d, 0x69, 0x6e, 0x6e, 0x65, 0x61, 0x70, 0x6f, 0x6c, 0x69, 0x73,
+    0x31, 0x14, 0x30, 0x12, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x0c, 0x0b, 0x43,
+    0x6f, 0x64, 0x65, 0x57, 0x65, 0x61, 0x76, 0x65, 0x72, 0x73, 0x31, 0x16,
+    0x30, 0x14, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x0d, 0x73, 0x65, 0x72,
+    0x76, 0x65, 0x72, 0x5f, 0x63, 0x6e, 0x2e, 0x6f, 0x72, 0x67, 0x31, 0x23,
+    0x30, 0x21, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09,
+    0x01, 0x16, 0x14, 0x74, 0x65, 0x73, 0x74, 0x40, 0x63, 0x6f, 0x64, 0x65,
+    0x77, 0x65, 0x61, 0x76, 0x65, 0x72, 0x73, 0x2e, 0x63, 0x6f, 0x6d, 0x30,
+    0x1e, 0x17, 0x0d, 0x32, 0x32, 0x30, 0x34, 0x31, 0x34, 0x31, 0x38, 0x35,
+    0x36, 0x32, 0x32, 0x5a, 0x17, 0x0d, 0x33, 0x32, 0x30, 0x34, 0x31, 0x31,
+    0x31, 0x38, 0x35, 0x36, 0x32, 0x32, 0x5a, 0x30, 0x81, 0x8a, 0x31, 0x0b,
+    0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31,
+    0x12, 0x30, 0x10, 0x06, 0x03, 0x55, 0x04, 0x08, 0x0c, 0x09, 0x4d, 0x69,
+    0x6e, 0x6e, 0x65, 0x73, 0x6f, 0x74, 0x61, 0x31, 0x14, 0x30, 0x12, 0x06,
+    0x03, 0x55, 0x04, 0x07, 0x0c, 0x0b, 0x4d, 0x69, 0x6e, 0x6e, 0x65, 0x61,
+    0x70, 0x6f, 0x6c, 0x69, 0x73, 0x31, 0x14, 0x30, 0x12, 0x06, 0x03, 0x55,
+    0x04, 0x0a, 0x0c, 0x0b, 0x43, 0x6f, 0x64, 0x65, 0x57, 0x65, 0x61, 0x76,
+    0x65, 0x72, 0x73, 0x31, 0x16, 0x30, 0x14, 0x06, 0x03, 0x55, 0x04, 0x03,
+    0x0c, 0x0d, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x5f, 0x63, 0x6e, 0x2e,
+    0x6f, 0x72, 0x67, 0x31, 0x23, 0x30, 0x21, 0x06, 0x09, 0x2a, 0x86, 0x48,
+    0x86, 0xf7, 0x0d, 0x01, 0x09, 0x01, 0x16, 0x14, 0x74, 0x65, 0x73, 0x74,
+    0x40, 0x63, 0x6f, 0x64, 0x65, 0x77, 0x65, 0x61, 0x76, 0x65, 0x72, 0x73,
+    0x2e, 0x63, 0x6f, 0x6d, 0x30, 0x81, 0x9f, 0x30, 0x0d, 0x06, 0x09, 0x2a,
+    0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x81,
+    0x8d, 0x00, 0x30, 0x81, 0x89, 0x02, 0x81, 0x81, 0x00, 0xcd, 0x7c, 0x05,
+    0xba, 0xad, 0xd0, 0xb0, 0x43, 0xcc, 0x47, 0x7d, 0x87, 0xaa, 0xb5, 0x89,
+    0x9f, 0x43, 0x94, 0xa0, 0x84, 0xc0, 0xc0, 0x5e, 0x05, 0x6d, 0x2f, 0x05,
+    0x21, 0x6b, 0x20, 0x39, 0x88, 0x06, 0x4e, 0xce, 0x76, 0xa7, 0x24, 0x77,
+    0x13, 0x71, 0x9b, 0x2a, 0x53, 0x04, 0x4f, 0x0f, 0xfc, 0x3f, 0x4f, 0xb1,
+    0x4e, 0xdc, 0xed, 0x96, 0xd4, 0x55, 0xbd, 0xcf, 0x25, 0xa6, 0x7c, 0xe3,
+    0x35, 0xbf, 0xeb, 0x30, 0xec, 0xef, 0x7f, 0x8e, 0xa1, 0xc6, 0xd3, 0xb2,
+    0x03, 0x62, 0x0a, 0x92, 0x87, 0x17, 0x52, 0x2d, 0x45, 0x2a, 0xdc, 0xdb,
+    0x87, 0xa5, 0x32, 0x4a, 0x78, 0x28, 0x4a, 0x51, 0xff, 0xdb, 0xd5, 0x20,
+    0x47, 0x7e, 0xc5, 0xbe, 0x1d, 0x01, 0x55, 0x13, 0x9f, 0xfb, 0x8e, 0x39,
+    0xd9, 0x1b, 0xe0, 0x34, 0x93, 0x43, 0x9c, 0x02, 0xa3, 0x0f, 0xb5, 0xdc,
+    0x9d, 0x86, 0x45, 0xc5, 0x4d, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x40,
+    0x30, 0x3e, 0x30, 0x1d, 0x06, 0x03,
+    0x55, 0x1d, 0x11, /* Subject Alternative Name OID */
+    0x04, 0x16, 0x30, 0x14, 0x82, 0x07, 0x65, 0x78, 0x31, 0x2e, 0x6f, 0x72,
+    0x67, 0x82, 0x09, 0x2a, 0x2e, 0x65, 0x78, 0x32, 0x2e, 0x6f, 0x72, 0x67,
+    0x30, 0x1d, 0x06, 0x03,
+    0x55, 0x1d, 0x12, /* Issuer Alternative Name OID */
+    0x04, 0x16, 0x30, 0x14, 0x82, 0x07, 0x65, 0x78, 0x33, 0x2e, 0x6f, 0x72,
+    0x67, 0x82, 0x09, 0x2a, 0x2e, 0x65, 0x78, 0x34, 0x2e, 0x6f, 0x72, 0x67,
+    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
+    0x04, 0x05, 0x00, 0x03, 0x81, 0x81, 0x00, 0xcc, 0xa3, 0x75, 0x67, 0x61,
+    0x63, 0x1d, 0x99, 0x16, 0xc6, 0x93, 0x35, 0xa4, 0x31, 0xb6, 0x05, 0x05,
+    0x77, 0x12, 0x15, 0x16, 0x78, 0xb3, 0xba, 0x6e, 0xde, 0xfc, 0x73, 0x7c,
+    0x5c, 0xdd, 0xdf, 0x92, 0xde, 0xa0, 0x86, 0xff, 0x77, 0x60, 0x99, 0x8f,
+    0x4a, 0x40, 0xa8, 0x6a, 0xdb, 0x6f, 0x30, 0xe5, 0xce, 0x82, 0x2f, 0xf7,
+    0x09, 0x17, 0xb2, 0xd3, 0x3a, 0x29, 0x9a, 0xd0, 0x73, 0x9c, 0x44, 0xa2,
+    0x19, 0xf3, 0x1d, 0x16, 0x1a, 0x45, 0x2c, 0x4b, 0x94, 0xf1, 0xb8, 0xb6,
+    0xc9, 0x82, 0x6c, 0x1f, 0xae, 0xbc, 0xd1, 0xbe, 0x78, 0xc9, 0x23, 0xf5,
+    0x51, 0x6c, 0x90, 0xbf, 0xa3, 0x5c, 0xa1, 0x3a, 0xd8, 0xe3, 0xcf, 0x82,
+    0x31, 0x78, 0x2b, 0xda, 0x99, 0xff, 0x23, 0x5b, 0xea, 0x59, 0xe0, 0x6d,
+    0xd1, 0x30, 0xfd, 0x96, 0x6a, 0x4d, 0x36, 0x72, 0x96, 0xd7, 0x4f, 0x01,
+    0xa9, 0x4d, 0x8f
+};
+#define CERT_V3_SAN_OID_OFFSET 534
+#define CERT_V3_IAN_OID_OFFSET 565
static char issuerStr[] =
"US, Minnesota, Minneapolis, CodeWeavers, Wine Development, localhost, aric@codeweavers.com";
static char issuerStrSemicolon[] =
@@ -134,33 +229,34 @@ static void test_CertRDNValueToStrA(void)
{
     CertRDNAttrEncoding attrs[] = {
     { "2.5.4.6", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin1), bin1 }, "US", FALSE },
+       { sizeof(bin1), bin1 }, "US" },
     { "2.5.4.8", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin2), bin2 }, "Minnesota", FALSE },
+       { sizeof(bin2), bin2 }, "Minnesota" },
     { "2.5.4.7", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin3), bin3 }, "Minneapolis", FALSE },
+       { sizeof(bin3), bin3 }, "Minneapolis" },
     { "2.5.4.10", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin4), bin4 }, "CodeWeavers", FALSE },
+       { sizeof(bin4), bin4 }, "CodeWeavers" },
     { "2.5.4.11", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin5), bin5 }, "Wine Development", FALSE },
+       { sizeof(bin5), bin5 }, "Wine Development" },
     { "2.5.4.3", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin6), bin6 }, "localhost", FALSE },
+       { sizeof(bin6), bin6 }, "localhost" },
     { "1.2.840.113549.1.9.1", CERT_RDN_IA5_STRING,
-       { sizeof(bin7), bin7 }, "aric@codeweavers.com", FALSE },
+       { sizeof(bin7), bin7 }, "aric@codeweavers.com" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin9), bin9 }, "abc\"def", FALSE },
+       { sizeof(bin9), bin9 }, "abc\"def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin10), bin10 }, "abc'def", FALSE },
+       { sizeof(bin10), bin10 }, "abc'def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin11), bin11 }, "abc, def", FALSE },
+       { sizeof(bin11), bin11 }, "abc, def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin12), bin12 }, " abc ", FALSE },
+       { sizeof(bin12), bin12 }, " abc " },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin13), bin13 }, "\"def\"", FALSE },
+       { sizeof(bin13), bin13 }, "\"def\"" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin14), bin14 }, "1;3", FALSE },
+       { sizeof(bin14), bin14 }, "1;3" },
     };
-    DWORD i, ret;
+    unsigned int i;
+    DWORD ret, len;
     char buffer[2000];
     CERT_RDN_VALUE_BLOB blob = { 0, NULL };
     static const char ePKI[] = "ePKI Root Certification Authority";
@@ -178,15 +274,21 @@ static void test_CertRDNValueToStrA(void)

     for (i = 0; i < ARRAY_SIZE(attrs); i++)
     {
-        ret = CertRDNValueToStrA(attrs[i].dwValueType, &attrs[i].Value,
+        len = CertRDNValueToStrA(attrs[i].dwValueType, &attrs[i].Value,
          buffer, sizeof(buffer));
-        todo_wine_if (attrs[i].todo)
-        {
-            ok(ret == strlen(attrs[i].str) + 1, "Expected length %d, got %ld\n",
-             lstrlenA(attrs[i].str) + 1, ret);
-            ok(!strcmp(buffer, attrs[i].str), "Expected %s, got %s\n",
-             attrs[i].str, buffer);
-        }
+        ok(len == strlen(attrs[i].str) + 1, "Expected length %d, got %ld\n",
+         lstrlenA(attrs[i].str) + 1, ret);
+        ok(!strcmp(buffer, attrs[i].str), "Expected %s, got %s\n",
+         attrs[i].str, buffer);
+        memset(buffer, 0xcc, sizeof(buffer));
+        ret = CertRDNValueToStrA(attrs[i].dwValueType, &attrs[i].Value, buffer, len - 1);
+        ok(ret == 1, "Unexpected ret %lu, expected 1, test %u.\n", ret, i);
+        ok(!buffer[0], "Unexpected value %#x, test %u.\n", buffer[0], i);
+        ok(!strncmp(buffer + 1, attrs[i].str + 1, len - 2), "Strings do not match, test %u.\n", i);
+        memset(buffer, 0xcc, sizeof(buffer));
+        ret = CertRDNValueToStrA(attrs[i].dwValueType, &attrs[i].Value, buffer, 0);
+        ok(ret == len, "Unexpected ret %lu, expected %lu, test %u.\n", ret, len, i);
+        ok((unsigned char)buffer[0] == 0xcc, "Unexpected value %#x, test %u.\n", buffer[0], i);
     }
     blob.pbData = bin8;
     blob.cbData = sizeof(bin8);
@@ -202,33 +304,34 @@ static void test_CertRDNValueToStrW(void)
     static const WCHAR ePKIW[] = L"ePKI Root Certification Authority";
     CertRDNAttrEncodingW attrs[] = {
     { "2.5.4.6", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin1), bin1 }, L"US", FALSE },
+       { sizeof(bin1), bin1 }, L"US" },
     { "2.5.4.8", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin2), bin2 }, L"Minnesota", FALSE },
+       { sizeof(bin2), bin2 }, L"Minnesota" },
     { "2.5.4.7", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin3), bin3 }, L"Minneapolis", FALSE },
+       { sizeof(bin3), bin3 }, L"Minneapolis" },
     { "2.5.4.10", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin4), bin4 }, L"CodeWeavers", FALSE },
+       { sizeof(bin4), bin4 }, L"CodeWeavers" },
     { "2.5.4.11", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin5), bin5 }, L"Wine Development", FALSE },
+       { sizeof(bin5), bin5 }, L"Wine Development" },
     { "2.5.4.3", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin6), bin6 }, L"localhost", FALSE },
+       { sizeof(bin6), bin6 }, L"localhost" },
     { "1.2.840.113549.1.9.1", CERT_RDN_IA5_STRING,
-       { sizeof(bin7), bin7 }, L"aric@codeweavers.com", FALSE },
+       { sizeof(bin7), bin7 }, L"aric@codeweavers.com" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin9), bin9 }, L"abc\"def", FALSE },
+       { sizeof(bin9), bin9 }, L"abc\"def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin10), bin10 }, L"abc'def", FALSE },
+       { sizeof(bin10), bin10 }, L"abc'def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin11), bin11 }, L"abc, def", FALSE },
+       { sizeof(bin11), bin11 }, L"abc, def" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin12), bin12 }, L" abc ", FALSE },
+       { sizeof(bin12), bin12 }, L" abc " },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin13), bin13 }, L"\"def\"", FALSE },
+       { sizeof(bin13), bin13 }, L"\"def\"" },
     { "0", CERT_RDN_PRINTABLE_STRING,
-       { sizeof(bin14), bin14 }, L"1;3", FALSE },
+       { sizeof(bin14), bin14 }, L"1;3" },
     };
-    DWORD i, ret;
+    unsigned int i;
+    DWORD ret, len;
     WCHAR buffer[2000];
     CERT_RDN_VALUE_BLOB blob = { 0, NULL };

@@ -245,14 +348,20 @@ static void test_CertRDNValueToStrW(void)

     for (i = 0; i < ARRAY_SIZE(attrs); i++)
     {
-        ret = CertRDNValueToStrW(attrs[i].dwValueType, &attrs[i].Value, buffer, ARRAY_SIZE(buffer));
-        todo_wine_if (attrs[i].todo)
-        {
-            ok(ret == lstrlenW(attrs[i].str) + 1,
-             "Expected length %d, got %ld\n", lstrlenW(attrs[i].str) + 1, ret);
-            ok(!lstrcmpW(buffer, attrs[i].str), "Expected %s, got %s\n",
-             wine_dbgstr_w(attrs[i].str), wine_dbgstr_w(buffer));
-        }
+        len = CertRDNValueToStrW(attrs[i].dwValueType, &attrs[i].Value, buffer, ARRAY_SIZE(buffer));
+        ok(len == lstrlenW(attrs[i].str) + 1,
+         "Expected length %d, got %ld\n", lstrlenW(attrs[i].str) + 1, ret);
+        ok(!lstrcmpW(buffer, attrs[i].str), "Expected %s, got %s\n",
+         wine_dbgstr_w(attrs[i].str), wine_dbgstr_w(buffer));
+        memset(buffer, 0xcc, sizeof(buffer));
+        ret = CertRDNValueToStrW(attrs[i].dwValueType, &attrs[i].Value, buffer, len - 1);
+        ok(ret == 1, "Unexpected ret %lu, expected 1, test %u.\n", ret, i);
+        ok(!buffer[0], "Unexpected value %#x, test %u.\n", buffer[0], i);
+        ok(buffer[1] == 0xcccc, "Unexpected value %#x, test %u.\n", buffer[1], i);
+        memset(buffer, 0xcc, sizeof(buffer));
+        ret = CertRDNValueToStrW(attrs[i].dwValueType, &attrs[i].Value, buffer, 0);
+        ok(ret == len, "Unexpected ret %lu, expected %lu, test %u.\n", ret, len, i);
+        ok(buffer[0] == 0xcccc, "Unexpected value %#x, test %u.\n", buffer[0], i);
     }
     blob.pbData = bin8;
     blob.cbData = sizeof(bin8);
@@ -264,24 +373,27 @@ static void test_CertRDNValueToStrW(void)
          wine_dbgstr_w(ePKIW), wine_dbgstr_w(buffer));
}

-static void test_NameToStrConversionA(PCERT_NAME_BLOB pName, DWORD dwStrType,
- LPCSTR expected, BOOL todo)
+#define test_NameToStrConversionA(a, b, c) test_NameToStrConversionA_(__LINE__, a, b, c)
+static void test_NameToStrConversionA_(unsigned int line, PCERT_NAME_BLOB pName, DWORD dwStrType, LPCSTR expected)
{
-    char buffer[2000] = { 0 };
-    DWORD i;
-
-    i = CertNameToStrA(X509_ASN_ENCODING, pName, dwStrType, NULL, 0);
-    todo_wine_if (todo)
-        ok(i == strlen(expected) + 1, "Expected %d chars, got %ld\n",
-         lstrlenA(expected) + 1, i);
-    i = CertNameToStrA(X509_ASN_ENCODING,pName, dwStrType, buffer,
-     sizeof(buffer));
-    todo_wine_if (todo)
-        ok(i == strlen(expected) + 1, "Expected %d chars, got %ld\n",
-         lstrlenA(expected) + 1, i);
-    todo_wine_if (todo)
-        ok(!strcmp(buffer, expected), "Expected %s, got %s\n", expected,
-         buffer);
+    char buffer[2000];
+    DWORD len, retlen;
+    len = CertNameToStrA(X509_ASN_ENCODING, pName, dwStrType, NULL, 0);
+    ok(len == strlen(expected) + 1, "line %u: Expected %d chars, got %ld.\n", line, lstrlenA(expected) + 1, len);
+    len = CertNameToStrA(X509_ASN_ENCODING,pName, dwStrType, buffer, sizeof(buffer));
+    ok(len == strlen(expected) + 1, "line %u: Expected %d chars, got %ld.\n",  line, lstrlenA(expected) + 1, len);
+    ok(!strcmp(buffer, expected), "line %u: Expected %s, got %s.\n", line, expected, buffer);
+    memset(buffer, 0xcc, sizeof(buffer));
+    retlen = CertNameToStrA(X509_ASN_ENCODING, pName, dwStrType, buffer, len - 1);
+    ok(retlen == 1, "line %u: expected 1, got %lu\n", line, retlen);
+    ok(!buffer[0], "line %u: string is not zero terminated.\n", line);
+    memset(buffer, 0xcc, sizeof(buffer));
+    retlen = CertNameToStrA(X509_ASN_ENCODING, pName, dwStrType, buffer, 0);
+    ok(retlen == len, "line %u: expected %lu chars, got %lu\n", line, len - 1, retlen);
+    ok((unsigned char)buffer[0] == 0xcc, "line %u: got %s\n", line, wine_dbgstr_a(buffer));
}

static BYTE encodedSimpleCN[] = {
@@ -354,98 +466,98 @@ static void test_CertNameToStrA(void)
          "Expected positive return and ERROR_SUCCESS, got %ld - %08lx\n",
          ret, GetLastError());

+        test_NameToStrConversionA(&context->pCertInfo->Issuer, CERT_SIMPLE_NAME_STR, issuerStr);
          test_NameToStrConversionA(&context->pCertInfo->Issuer,
-         CERT_SIMPLE_NAME_STR, issuerStr, FALSE);
-        test_NameToStrConversionA(&context->pCertInfo->Issuer,
-         CERT_SIMPLE_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG,
-         issuerStrSemicolon, FALSE);
+         CERT_SIMPLE_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG, issuerStrSemicolon);
          test_NameToStrConversionA(&context->pCertInfo->Issuer,
-         CERT_SIMPLE_NAME_STR | CERT_NAME_STR_CRLF_FLAG,
-         issuerStrCRLF, FALSE);
-        test_NameToStrConversionA(&context->pCertInfo->Subject,
-         CERT_OID_NAME_STR, subjectStr, FALSE);
+         CERT_SIMPLE_NAME_STR | CERT_NAME_STR_CRLF_FLAG, issuerStrCRLF);
+        test_NameToStrConversionA(&context->pCertInfo->Subject, CERT_OID_NAME_STR, subjectStr);
          test_NameToStrConversionA(&context->pCertInfo->Subject,
-         CERT_OID_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG,
-         subjectStrSemicolon, FALSE);
+         CERT_OID_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG, subjectStrSemicolon);
          test_NameToStrConversionA(&context->pCertInfo->Subject,
-         CERT_OID_NAME_STR | CERT_NAME_STR_CRLF_FLAG,
-         subjectStrCRLF, FALSE);
+         CERT_OID_NAME_STR | CERT_NAME_STR_CRLF_FLAG, subjectStrCRLF);
          test_NameToStrConversionA(&context->pCertInfo->Subject,
-         CERT_X500_NAME_STR, x500SubjectStr, FALSE);
+         CERT_X500_NAME_STR, x500SubjectStr);
          test_NameToStrConversionA(&context->pCertInfo->Subject,
          CERT_X500_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG | CERT_NAME_STR_REVERSE_FLAG,
-         x500SubjectStrSemicolonReverse, FALSE);
+         x500SubjectStrSemicolonReverse);

          CertFreeCertificateContext(context);
     }
     blob.pbData = encodedSimpleCN;
     blob.cbData = sizeof(encodedSimpleCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=1", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=1");
     blob.pbData = encodedSingleQuotedCN;
     blob.cbData = sizeof(encodedSingleQuotedCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN='1'", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "'1'", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN='1'");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "'1'");
     blob.pbData = encodedSpacedCN;
     blob.cbData = sizeof(encodedSpacedCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\" 1 \"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\" 1 \"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\" 1 \"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\" 1 \"");
     blob.pbData = encodedQuotedCN;
     blob.cbData = sizeof(encodedQuotedCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"\"\"1\"\"\"",
-     FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"\"\"1\"\"\"",
-     FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"\"\"1\"\"\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"\"\"1\"\"\"");
     blob.pbData = encodedMultipleAttrCN;
     blob.cbData = sizeof(encodedMultipleAttrCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"1+2\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"1+2\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"1+2\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"1+2\"");
     blob.pbData = encodedCommaCN;
     blob.cbData = sizeof(encodedCommaCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a,b\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a,b\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a,b\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a,b\"");
     blob.pbData = encodedEqualCN;
     blob.cbData = sizeof(encodedEqualCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a=b\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a=b\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a=b\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a=b\"");
     blob.pbData = encodedLessThanCN;
     blob.cbData = sizeof(encodedLessThanCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"<\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"<\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"<\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"<\"");
     blob.pbData = encodedGreaterThanCN;
     blob.cbData = sizeof(encodedGreaterThanCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\">\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\">\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\">\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\">\"");
     blob.pbData = encodedHashCN;
     blob.cbData = sizeof(encodedHashCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"#\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"#\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"#\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"#\"");
     blob.pbData = encodedSemiCN;
     blob.cbData = sizeof(encodedSemiCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\";\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\";\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\";\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\";\"");
     blob.pbData = encodedNewlineCN;
     blob.cbData = sizeof(encodedNewlineCN);
-    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a\nb\"", FALSE);
-    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a\nb\"", FALSE);
+    test_NameToStrConversionA(&blob, CERT_X500_NAME_STR, "CN=\"a\nb\"");
+    test_NameToStrConversionA(&blob, CERT_SIMPLE_NAME_STR, "\"a\nb\"");
}

-static void test_NameToStrConversionW(PCERT_NAME_BLOB pName, DWORD dwStrType,
- LPCWSTR expected, BOOL todo)
+#define test_NameToStrConversionW(a, b, c) test_NameToStrConversionW_(__LINE__, a, b, c)
+static void test_NameToStrConversionW_(unsigned int line, PCERT_NAME_BLOB pName, DWORD dwStrType, LPCWSTR expected)
{
-    WCHAR buffer[2000] = { 0 };
-    DWORD i;
-
-    i = CertNameToStrW(X509_ASN_ENCODING,pName, dwStrType, NULL, 0);
-    todo_wine_if (todo)
-        ok(i == lstrlenW(expected) + 1, "Expected %d chars, got %ld\n",
-         lstrlenW(expected) + 1, i);
-    i = CertNameToStrW(X509_ASN_ENCODING,pName, dwStrType, buffer, ARRAY_SIZE(buffer));
-    todo_wine_if (todo)
-        ok(i == lstrlenW(expected) + 1, "Expected %d chars, got %ld\n",
-         lstrlenW(expected) + 1, i);
-    todo_wine_if (todo)
-        ok(!lstrcmpW(buffer, expected), "Expected %s, got %s\n",
-         wine_dbgstr_w(expected), wine_dbgstr_w(buffer));
+    DWORD len, retlen, expected_len;
+    WCHAR buffer[2000];
+    expected_len = wcslen(expected) + 1;
+    memset(buffer, 0xcc, sizeof(buffer));
+    len = CertNameToStrW(X509_ASN_ENCODING, pName, dwStrType, NULL, 0);
+    ok(len == expected_len, "line %u: expected %lu chars, got %lu\n", line, expected_len, len);
+    retlen = CertNameToStrW(X509_ASN_ENCODING, pName, dwStrType, buffer, ARRAY_SIZE(buffer));
+    ok(retlen == len, "line %u: expected %lu chars, got %lu.\n", line, len, retlen);
+    ok(!wcscmp(buffer, expected), "Expected %s, got %s\n", wine_dbgstr_w(expected), wine_dbgstr_w(buffer));
+    memset(buffer, 0xcc, sizeof(buffer));
+    retlen = CertNameToStrW(X509_ASN_ENCODING, pName, dwStrType, buffer, len - 1);
+    ok(retlen == len - 1, "line %u: expected %lu chars, got %lu\n", line, len - 1, retlen);
+    ok(!wcsncmp(buffer, expected, retlen - 1), "line %u: expected %s, got %s\n",
+            line, wine_dbgstr_w(expected), wine_dbgstr_w(buffer));
+    ok(!buffer[retlen - 1], "line %u: string is not zero terminated.\n", line);
+    memset(buffer, 0xcc, sizeof(buffer));
+    retlen = CertNameToStrW(X509_ASN_ENCODING, pName, dwStrType, buffer, 0);
+    ok(retlen == len, "line %u: expected %lu chars, got %lu\n", line, len - 1, retlen);
+    ok(buffer[0] == 0xcccc, "line %u: got %s\n", line, wine_dbgstr_w(buffer));
}

static void test_CertNameToStrW(void)
@@ -479,95 +591,79 @@ static void test_CertNameToStrW(void)

          test_NameToStrConversionW(&context->pCertInfo->Issuer,
          CERT_SIMPLE_NAME_STR,
-         L"US, Minnesota, Minneapolis, CodeWeavers, Wine Development, localhost, aric@codeweavers.com", FALSE);
+         L"US, Minnesota, Minneapolis, CodeWeavers, Wine Development, localhost, aric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Issuer,
          CERT_SIMPLE_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG,
-         L"US; Minnesota; Minneapolis; CodeWeavers; Wine Development; localhost; aric@codeweavers.com", FALSE);
+         L"US; Minnesota; Minneapolis; CodeWeavers; Wine Development; localhost; aric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Issuer,
          CERT_SIMPLE_NAME_STR | CERT_NAME_STR_CRLF_FLAG,
-         L"US\r\nMinnesota\r\nMinneapolis\r\nCodeWeavers\r\nWine Development\r\nlocalhost\r\naric@codeweavers.com",
-         FALSE);
+         L"US\r\nMinnesota\r\nMinneapolis\r\nCodeWeavers\r\nWine Development\r\nlocalhost\r\naric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Subject,
          CERT_OID_NAME_STR,
          L"2.5.4.6=US, 2.5.4.8=Minnesota, 2.5.4.7=Minneapolis, 2.5.4.10=CodeWeavers, 2.5.4.11=Wine Development,"
-          " 2.5.4.3=localhost, 1.2.840.113549.1.9.1=aric@codeweavers.com", FALSE);
+          " 2.5.4.3=localhost, 1.2.840.113549.1.9.1=aric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Subject,
          CERT_OID_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG,
          L"2.5.4.6=US; 2.5.4.8=Minnesota; 2.5.4.7=Minneapolis; 2.5.4.10=CodeWeavers; 2.5.4.11=Wine Development;"
-          " 2.5.4.3=localhost; 1.2.840.113549.1.9.1=aric@codeweavers.com", FALSE);
+          " 2.5.4.3=localhost; 1.2.840.113549.1.9.1=aric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Subject,
          CERT_OID_NAME_STR | CERT_NAME_STR_CRLF_FLAG,
          L"2.5.4.6=US\r\n2.5.4.8=Minnesota\r\n2.5.4.7=Minneapolis\r\n2.5.4.10=CodeWeavers\r\n2.5.4.11=Wine "
-          "Development\r\n2.5.4.3=localhost\r\n1.2.840.113549.1.9.1=aric@codeweavers.com", FALSE);
+          "Development\r\n2.5.4.3=localhost\r\n1.2.840.113549.1.9.1=aric@codeweavers.com");
          test_NameToStrConversionW(&context->pCertInfo->Subject,
          CERT_X500_NAME_STR | CERT_NAME_STR_SEMICOLON_FLAG | CERT_NAME_STR_REVERSE_FLAG,
          L"E=aric@codeweavers.com; CN=localhost; OU=Wine Development; O=CodeWeavers; L=Minneapolis; S=Minnesota; "
-          "C=US", FALSE);
+          "C=US");

          CertFreeCertificateContext(context);
     }
     blob.pbData = encodedSimpleCN;
     blob.cbData = sizeof(encodedSimpleCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=1", FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=1");
     blob.pbData = encodedSingleQuotedCN;
     blob.cbData = sizeof(encodedSingleQuotedCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN='1'",
-     FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR,
-     L"'1'", FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN='1'");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"'1'");
     blob.pbData = encodedSpacedCN;
     blob.cbData = sizeof(encodedSpacedCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\" 1 \"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\" 1 \"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\" 1 \"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\" 1 \"");
     blob.pbData = encodedQuotedCN;
     blob.cbData = sizeof(encodedQuotedCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"\"\"1\"\"\"",
-     FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"\"\"1\"\"\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"\"\"1\"\"\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"\"\"1\"\"\"");
     blob.pbData = encodedMultipleAttrCN;
     blob.cbData = sizeof(encodedMultipleAttrCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"1+2\"",
-     FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR,
-     L"\"1+2\"", FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"1+2\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"1+2\"");
     blob.pbData = encodedCommaCN;
     blob.cbData = sizeof(encodedCommaCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a,b\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a,b\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a,b\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a,b\"");
     blob.pbData = encodedEqualCN;
     blob.cbData = sizeof(encodedEqualCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a=b\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a=b\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a=b\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a=b\"");
     blob.pbData = encodedLessThanCN;
     blob.cbData = sizeof(encodedLessThanCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"<\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"<\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"<\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"<\"");
     blob.pbData = encodedGreaterThanCN;
     blob.cbData = sizeof(encodedGreaterThanCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\">\"",
-     FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR,
-     L"\">\"", FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\">\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\">\"");
     blob.pbData = encodedHashCN;
     blob.cbData = sizeof(encodedHashCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"#\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"#\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"#\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"#\"");
     blob.pbData = encodedSemiCN;
     blob.cbData = sizeof(encodedSemiCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\";\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\";\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\";\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\";\"");
     blob.pbData = encodedNewlineCN;
     blob.cbData = sizeof(encodedNewlineCN);
-    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a\nb\"", FALSE);
-    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a\nb\"",
-     FALSE);
+    test_NameToStrConversionW(&blob, CERT_X500_NAME_STR, L"CN=\"a\nb\"");
+    test_NameToStrConversionW(&blob, CERT_SIMPLE_NAME_STR, L"\"a\nb\"");
}

struct StrToNameA
@@ -747,153 +843,140 @@ static void test_CertStrToNameW(void)
     }
}

-static void test_CertGetNameStringA(void)
+#define test_CertGetNameString_value(a, b, c, d, e) test_CertGetNameString_value_(__LINE__, a, b, c, d, e)
+static void test_CertGetNameString_value_(unsigned int line, PCCERT_CONTEXT context, DWORD type, DWORD flags,
+        void *type_para, const char *expected)
{
+    DWORD len, retlen, expected_len;
+    WCHAR expectedW[512];
+    WCHAR strW[512];
+    char str[512];
+    expected_len = 0;
+    while(expected[expected_len])
+        while((expectedW[expected_len] = expected[expected_len]))
+            ++expected_len;
+        if (!(flags & CERT_NAME_SEARCH_ALL_NAMES_FLAG))
+            break;
+        expectedW[expected_len++] = 0;
+    expectedW[expected_len++] = 0;
+    len = CertGetNameStringA(context, type, flags, type_para, NULL, 0);
+    ok(len == expected_len, "line %u: unexpected length %ld, expected %ld.\n", line, len, expected_len);
+    memset(str, 0xcc, len);
+    retlen = CertGetNameStringA(context, type, flags, type_para, str, len);
+    ok(retlen == len, "line %u: unexpected len %lu, expected %lu.\n", line, retlen, len);
+    ok(!memcmp(str, expected, expected_len), "line %u: unexpected value %s.\n", line, debugstr_an(str, expected_len));
+    str[0] = str[1] = 0xcc;
+    retlen = CertGetNameStringA(context, type, flags, type_para, str, len - 1);
+    ok(retlen == 1, "line %u: Unexpected len %lu, expected 1.\n", line, retlen);
+    if (len == 1) return;
+    ok(!str[0], "line %u: unexpected str[0] %#x.\n", line, str[0]);
+    ok(str[1] == expected[1], "line %u: unexpected str[1] %#x.\n", line, str[1]);
+    ok(!memcmp(str + 1, expected + 1, len - 2),
+            "line %u: str %s, string data mismatch.\n", line, debugstr_a(str + 1));
+    retlen = CertGetNameStringA(context, type, flags, type_para, str, 0);
+    ok(retlen == len, "line %u: Unexpected len %lu, expected 1.\n", line, retlen);
+    memset(strW, 0xcc, len * sizeof(*strW));
+    retlen = CertGetNameStringW(context, type, flags, type_para, strW, len);
+    ok(retlen == expected_len, "line %u: unexpected len %lu, expected %lu.\n", line, retlen, expected_len);
+    ok(!memcmp(strW, expectedW, len * sizeof(*strW)), "line %u: unexpected value %s.\n", line, debugstr_wn(strW, len));
+    strW[0] = strW[1] = 0xcccc;
+    retlen = CertGetNameStringW(context, type, flags, type_para, strW, len - 1);
+    ok(retlen == len - 1, "line %u: unexpected len %lu, expected %lu.\n", line, retlen, len - 1);
+    if (flags & CERT_NAME_SEARCH_ALL_NAMES_FLAG)
+    {
+        ok(!memcmp(strW, expectedW, (retlen - 2) * sizeof(*strW)),
+                "line %u: str %s, string data mismatch.\n", line, debugstr_wn(strW, retlen - 2));
+        ok(!strW[retlen - 2], "line %u: string is not zero terminated.\n", line);
+        ok(!strW[retlen - 1], "line %u: string sequence is not zero terminated.\n", line);
+        retlen = CertGetNameStringW(context, type, flags, type_para, strW, 1);
+        ok(retlen == 1, "line %u: unexpected len %lu, expected %lu.\n", line, retlen, len - 1);
+        ok(!strW[retlen - 1], "line %u: string sequence is not zero terminated.\n", line);
+    }
+    else
+    {
+        ok(!memcmp(strW, expectedW, (retlen - 1) * sizeof(*strW)),
+                "line %u: str %s, string data mismatch.\n", line, debugstr_wn(strW, retlen - 1));
+        ok(!strW[retlen - 1], "line %u: string is not zero terminated.\n", line);
+    }
+    retlen = CertGetNameStringA(context, type, flags, type_para, NULL, len - 1);
+    ok(retlen == len, "line %u: unexpected len %lu, expected %lu\n", line, retlen, len);
+    retlen = CertGetNameStringW(context, type, flags, type_para, NULL, len - 1);
+    ok(retlen == len, "line %u: unexpected len %lu, expected %lu\n", line, retlen, len);
+static void test_CertGetNameString(void)
+    static const char aric[] = "aric@codeweavers.com";
+    static const char localhost[] = "localhost";
     PCCERT_CONTEXT context;
+    DWORD len, type;

     context = CertCreateCertificateContext(X509_ASN_ENCODING, cert,
     sizeof(cert));
-    ok(context != NULL, "CertCreateCertificateContext failed: %08lx\n",
-     GetLastError());
-    if (context)
-    {
-        static const char aric[] = "aric@codeweavers.com";
-        static const char localhost[] = "localhost";
-        DWORD len, type;
-        LPSTR str;
-
-        /* Bad string types/types missing from the cert */
-        len = CertGetNameStringA(NULL, 0, 0, NULL, NULL, 0);
-        ok(len == 1, "expected 1, got %ld\n", len);
-        len = CertGetNameStringA(context, 0, 0, NULL, NULL, 0);
-        ok(len == 1, "expected 1, got %ld\n", len);
-        len = CertGetNameStringA(context, CERT_NAME_URL_TYPE, 0, NULL, NULL,
-         0);
-        ok(len == 1, "expected 1, got %ld\n", len);
-
-        len = CertGetNameStringA(context, CERT_NAME_EMAIL_TYPE, 0, NULL, NULL,
-         0);
-        ok(len == strlen(aric) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_EMAIL_TYPE, 0, NULL,
-             str, len);
-            ok(!strcmp(str, aric), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-
-        len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, NULL, NULL,
-         0);
-        ok(len == strlen(issuerStr) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, NULL,
-             str, len);
-            ok(!strcmp(str, issuerStr), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-        type = 0;
-        len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, &type, NULL,
-         0);
-        ok(len == strlen(issuerStr) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, &type,
-             str, len);
-            ok(!strcmp(str, issuerStr), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-        type = CERT_OID_NAME_STR;
-        len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, &type, NULL,
-         0);
-        ok(len == strlen(subjectStr) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_RDN_TYPE, 0, &type,
-             str, len);
-            ok(!strcmp(str, subjectStr), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-
-        len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0, NULL, NULL,
-         0);
-        ok(len == strlen(aric) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0, NULL,
-             str, len);
-            ok(!strcmp(str, aric), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-        len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0,
-         (void *)szOID_RSA_emailAddr, NULL, 0);
-        ok(len == strlen(aric) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0,
-             (void *)szOID_RSA_emailAddr, str, len);
-            ok(!strcmp(str, aric), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-        len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0,
-         (void *)szOID_COMMON_NAME, NULL, 0);
-        ok(len == strlen(localhost) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_ATTR_TYPE, 0,
-             (void *)szOID_COMMON_NAME, str, len);
-            ok(!strcmp(str, localhost), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-
-        len = CertGetNameStringA(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0,
-         NULL, NULL, 0);
-        ok(len == strlen(localhost) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_SIMPLE_DISPLAY_TYPE,
-             0, NULL, str, len);
-            ok(!strcmp(str, localhost), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-
-        len = CertGetNameStringA(context, CERT_NAME_FRIENDLY_DISPLAY_TYPE, 0,
-         NULL, NULL, 0);
-        ok(len == strlen(localhost) + 1, "unexpected length %ld\n", len);
-        str = HeapAlloc(GetProcessHeap(), 0, len);
-        if (str)
-        {
-            len = CertGetNameStringA(context, CERT_NAME_FRIENDLY_DISPLAY_TYPE,
-             0, NULL, str, len);
-            ok(!strcmp(str, localhost), "unexpected value %s\n", str);
-            HeapFree(GetProcessHeap(), 0, str);
-        }
-
-        len = CertGetNameStringA(context, CERT_NAME_DNS_TYPE, 0, NULL, NULL,
-         0);
-        ok(len == strlen(localhost) + 1, "unexpected length %ld\n", len);
-        if (len > 1)
-        {
-            str = HeapAlloc(GetProcessHeap(), 0, len);
-            if (str)
-            {
-                len = CertGetNameStringA(context, CERT_NAME_DNS_TYPE, 0, NULL,
-                 str, len);
-                ok(!strcmp(str, localhost), "unexpected value %s\n", str);
-                HeapFree(GetProcessHeap(), 0, str);
-            }
-        }
-
-        CertFreeCertificateContext(context);
-    }
+    ok(!!context, "CertCreateCertificateContext failed, err %lu\n", GetLastError());
+    /* Bad string types/types missing from the cert */
+    len = CertGetNameStringA(NULL, 0, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    len = CertGetNameStringA(context, 0, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    len = CertGetNameStringA(context, CERT_NAME_URL_TYPE, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    len = CertGetNameStringW(NULL, 0, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    len = CertGetNameStringW(context, 0, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    len = CertGetNameStringW(context, CERT_NAME_URL_TYPE, 0, NULL, NULL, 0);
+    ok(len == 1, "expected 1, got %lu\n", len);
+    test_CertGetNameString_value(context, CERT_NAME_EMAIL_TYPE, 0, NULL, aric);
+    test_CertGetNameString_value(context, CERT_NAME_RDN_TYPE, 0, NULL, issuerStr);
+    type = 0;
+    test_CertGetNameString_value(context, CERT_NAME_RDN_TYPE, 0, &type, issuerStr);
+    type = CERT_OID_NAME_STR;
+    test_CertGetNameString_value(context, CERT_NAME_RDN_TYPE, 0, &type, subjectStr);
+    test_CertGetNameString_value(context, CERT_NAME_ATTR_TYPE, 0, NULL, aric);
+    test_CertGetNameString_value(context, CERT_NAME_ATTR_TYPE, 0, (void *)szOID_RSA_emailAddr, aric);
+    test_CertGetNameString_value(context, CERT_NAME_ATTR_TYPE, 0, (void *)szOID_COMMON_NAME, localhost);
+    test_CertGetNameString_value(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, NULL, localhost);
+    test_CertGetNameString_value(context, CERT_NAME_FRIENDLY_DISPLAY_TYPE, 0, NULL, localhost);
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, 0, NULL, localhost);
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, CERT_NAME_SEARCH_ALL_NAMES_FLAG, NULL, "localhost\0");
+    test_CertGetNameString_value(context, CERT_NAME_EMAIL_TYPE, CERT_NAME_SEARCH_ALL_NAMES_FLAG, NULL, "");
+    test_CertGetNameString_value(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, CERT_NAME_SEARCH_ALL_NAMES_FLAG, NULL, "");
+    CertFreeCertificateContext(context);
+    ok(cert_v3[CERT_V3_SAN_OID_OFFSET] == 0x55, "Incorrect CERT_V3_SAN_OID_OFFSET.\n");
+    ok(cert_v3[CERT_V3_IAN_OID_OFFSET] == 0x55, "Incorrect CERT_V3_IAN_OID_OFFSET.\n");
+    cert_v3[CERT_V3_SAN_OID_OFFSET + 2] = 7; /* legacy OID_SUBJECT_ALT_NAME */
+    cert_v3[CERT_V3_IAN_OID_OFFSET + 2] = 8; /* legacy OID_ISSUER_ALT_NAME */
+    context = CertCreateCertificateContext(X509_ASN_ENCODING, cert_v3, sizeof(cert_v3));
+    ok(!!context, "CertCreateCertificateContext failed, err %lu\n", GetLastError());
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, 0, NULL, "ex1.org");
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, CERT_NAME_ISSUER_FLAG, NULL, "ex3.org");
+    CertFreeCertificateContext(context);
+    cert_v3[CERT_V3_SAN_OID_OFFSET + 2] = 17; /* OID_SUBJECT_ALT_NAME2 */
+    cert_v3[CERT_V3_IAN_OID_OFFSET + 2] = 18; /* OID_ISSUER_ALT_NAME2 */
+    context = CertCreateCertificateContext(X509_ASN_ENCODING, cert_v3, sizeof(cert_v3));
+    ok(!!context, "CertCreateCertificateContext failed, err %lu\n", GetLastError());
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, 0, NULL, "ex1.org");
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, CERT_NAME_ISSUER_FLAG, NULL, "ex3.org");
+    test_CertGetNameString_value(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, NULL, "server_cn.org");
+    test_CertGetNameString_value(context, CERT_NAME_ATTR_TYPE, 0, (void *)szOID_SUR_NAME, "");
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, CERT_NAME_SEARCH_ALL_NAMES_FLAG,
+            NULL, "ex1.org\0*.ex2.org\0");
+    test_CertGetNameString_value(context, CERT_NAME_DNS_TYPE, CERT_NAME_SEARCH_ALL_NAMES_FLAG | CERT_NAME_ISSUER_FLAG,
+            NULL, "ex3.org\0*.ex4.org\0");
+    CertFreeCertificateContext(context);
}

START_TEST(str)
@@ -904,5 +987,5 @@ START_TEST(str)
     test_CertNameToStrW();
     test_CertStrToNameA();
     test_CertStrToNameW();
-    test_CertGetNameStringA();
+    test_CertGetNameString();
}
diff --git a/wine/dlls/crypt32/unixlib.c b/wine/dlls/crypt32/unixlib.c
index 069cb0498..9a36d12f2 100644
--- a/wine/dlls/crypt32/unixlib.c
+++ b/wine/dlls/crypt32/unixlib.c
@@ -95,21 +95,7 @@ static NTSTATUS process_attach( void *args )
          setenv("GNUTLS_SYSTEM_PRIORITY_FILE", "/dev/null", 0);
     }

-if (1) { /* CROSSOVER HACK - bug 10151 */
-    const char *libgnutls_name_candidates[] = {SONAME_LIBGNUTLS,
-                                               "libgnutls.so.30",
-                                               "libgnutls.so.28",
-                                               "libgnutls-deb0.so.28",
-                                               "libgnutls.so.26",
-                                               NULL};
-    int i;
-    for (i=0; libgnutls_name_candidates[i] && !libgnutls_handle; i++)
-        libgnutls_handle = dlopen(libgnutls_name_candidates[i], RTLD_NOW);
-}
-else
-    libgnutls_handle = dlopen( SONAME_LIBGNUTLS, RTLD_NOW );
-
-    if (!libgnutls_handle)
+    if (!(libgnutls_handle = dlopen( SONAME_LIBGNUTLS, RTLD_NOW )))
     {
          ERR_(winediag)( "failed to load libgnutls, no support for pfx import/export\n" );
          return STATUS_DLL_NOT_FOUND;
diff --git a/wine/dlls/cryptnet/cryptnet_main.c b/wine/dlls/cryptnet/cryptnet_main.c
index 6654ef77c..19de1ed2d 100644
--- a/wine/dlls/cryptnet/cryptnet_main.c
+++ b/wine/dlls/cryptnet/cryptnet_main.c
@@ -1690,6 +1690,15 @@ static DWORD verify_cert_revocation_from_dist_points_ext(const CRYPT_DATA_BLOB *
     const CRL_CONTEXT *crl;
     DWORD timeout = 0;

+    if (!params || !params->pIssuerCert)
+    {
+        TRACE("no issuer certificate\n");
+        return CRYPT_E_REVOCATION_OFFLINE;
+    if (find_cached_revocation_status(&cert->pCertInfo->SerialNumber, time, status))
+        return status->dwError;
     if (!CRYPT_GetUrlFromCRLDistPointsExt(value, NULL, &url_array_size, NULL, NULL))
          return GetLastError();

@@ -1918,6 +1927,7 @@ static DWORD verify_signed_ocsp_response_info(const CERT_INFO *cert, const CERT_
     HCRYPTPROV prov = 0;
     HCRYPTHASH hash = 0;
     HCRYPTKEY key = 0;
+    DWORD algid;

     if (!CryptDecodeObjectEx(X509_ASN_ENCODING, OCSP_BASIC_SIGNED_RESPONSE, blob->pbData, blob->cbData,
                              CRYPT_DECODE_ALLOC_FLAG, NULL, &info, &size)) return GetLastError();
@@ -1925,7 +1935,7 @@ static DWORD verify_signed_ocsp_response_info(const CERT_INFO *cert, const CERT_
     if ((error = check_ocsp_response_info(cert, issuer, &info->ToBeSigned, &status))) goto done;

     alg = &info->SignatureInfo.SignatureAlgorithm;
-    if (!alg->pszObjId || strcmp(alg->pszObjId, szOID_RSA_SHA256RSA))
+    if (!alg->pszObjId || !(algid = CertOIDToAlgId(alg->pszObjId)))
     {
          FIXME("unhandled signature algorithm %s\n", debugstr_a(alg->pszObjId));
          error = CRYPT_E_NO_REVOCATION_CHECK;
@@ -1933,7 +1943,7 @@ static DWORD verify_signed_ocsp_response_info(const CERT_INFO *cert, const CERT_
     }

     if (!CryptAcquireContextW(&prov, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT)) goto done;
-    if (!CryptCreateHash(prov, CALG_SHA_256, 0, 0, &hash)) goto done;
+    if (!CryptCreateHash(prov, algid, 0, 0, &hash)) goto done;
     if (!CryptHashData(hash, info->ToBeSigned.pbData, info->ToBeSigned.cbData, 0)) goto done;

     sig = &info->SignatureInfo.Signature;
@@ -2136,22 +2146,19 @@ static DWORD verify_cert_revocation(const CERT_CONTEXT *cert, FILETIME *pTime,
     DWORD error = ERROR_SUCCESS;
     PCERT_EXTENSION ext;

-    if (find_cached_revocation_status(&cert->pCertInfo->SerialNumber, pTime, pRevStatus))
-        return pRevStatus->dwError;
-
-    if ((ext = CertFindExtension(szOID_CRL_DIST_POINTS,
-     cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension)))
+    if ((ext = CertFindExtension(szOID_AUTHORITY_INFO_ACCESS, cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension)))
     {
-        error = verify_cert_revocation_from_dist_points_ext(&ext->Value, cert,
-                pTime, dwFlags, pRevPara, pRevStatus);
+        error = verify_cert_revocation_from_aia_ext(&ext->Value, cert, pTime, dwFlags, pRevPara, pRevStatus);
+        TRACE("verify_cert_revocation_from_aia_ext() returned %08lx\n", error);
+        if (error == ERROR_SUCCESS || error == CRYPT_E_REVOKED) return error;
     }
-    else if ((ext = CertFindExtension(szOID_AUTHORITY_INFO_ACCESS,
-     cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension)))
+    if ((ext = CertFindExtension(szOID_CRL_DIST_POINTS, cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension)))
     {
-        error = verify_cert_revocation_from_aia_ext(&ext->Value, cert, pTime,
-                dwFlags, pRevPara, pRevStatus);
+        error = verify_cert_revocation_from_dist_points_ext(&ext->Value, cert, pTime, dwFlags, pRevPara, pRevStatus);
+        TRACE("verify_cert_revocation_from_dist_points_ext() returned %08lx\n", error);
+        if (error == ERROR_SUCCESS || error == CRYPT_E_REVOKED) return error;
     }
-    else
+    if (!ext)
     {
          if (pRevPara && pRevPara->hCrlStore && pRevPara->pIssuerCert)
          {
diff --git a/wine/dlls/kernel32/kernel32.spec b/wine/dlls/kernel32/kernel32.spec
index 2ae9ccdc9..3626c7409 100644
--- a/wine/dlls/kernel32/kernel32.spec
+++ b/wine/dlls/kernel32/kernel32.spec
@@ -370,6 +370,7 @@
@ stdcall -import DeleteProcThreadAttributeList(ptr)
# @ stub DisableThreadProfiling
@ stdcall DisassociateCurrentThreadFromCallback(ptr) NTDLL.TpDisassociateCallback
+@ stdcall DiscardVirtualMemory(ptr long) kernelbase.DiscardVirtualMemory
@ stdcall DeleteTimerQueue(long)
@ stdcall -import DeleteTimerQueueEx(long long)
@ stdcall -import DeleteTimerQueueTimer(long long long)
@@ -1470,6 +1471,7 @@
@ stdcall -import SetThreadGroupAffinity(long ptr ptr)
@ stdcall -import SetThreadIdealProcessor(long long)
@ stdcall -import SetThreadIdealProcessorEx(long ptr ptr)
+@ stdcall -import SetThreadInformation(long long ptr long)
@ stdcall -import SetThreadLocale(long)
@ stdcall -import SetThreadPreferredUILanguages(long ptr ptr)
@ stdcall -import SetThreadPriority(long long)
diff --git a/wine/dlls/kernelbase/kernelbase.spec b/wine/dlls/kernelbase/kernelbase.spec
index 00012198e..ae6bc842f 100644
--- a/wine/dlls/kernelbase/kernelbase.spec
+++ b/wine/dlls/kernelbase/kernelbase.spec
@@ -269,7 +269,7 @@
@ stdcall DisablePredefinedHandleTableInternal(long)
@ stdcall DisableThreadLibraryCalls(long)
@ stdcall DisassociateCurrentThreadFromCallback(ptr) ntdll.TpDisassociateCallback
-# @ stub DiscardVirtualMemory
+@ stdcall DiscardVirtualMemory(ptr long)
@ stdcall DisconnectNamedPipe(long)
@ stdcall DnsHostnameToComputerNameExW(wstr ptr ptr)
# @ stub DsBindWithSpnExW
@@ -1247,7 +1247,7 @@
@ stdcall QueryThreadpoolStackInformation(ptr ptr)
@ stdcall QueryUnbiasedInterruptTime(ptr) ntdll.RtlQueryUnbiasedInterruptTime
# @ stub QueryUnbiasedInterruptTimePrecise
-# @ stub QueryVirtualMemoryInformation
+@ stdcall QueryVirtualMemoryInformation(long ptr long ptr long ptr)
@ stdcall QueryWorkingSet(long ptr long)
@ stdcall QueryWorkingSetEx(long ptr long)
@ stdcall QueueUserAPC(ptr long long)
@@ -1519,7 +1519,7 @@
@ stdcall SetThreadGroupAffinity(long ptr ptr)
@ stdcall SetThreadIdealProcessor(long long)
@ stdcall SetThreadIdealProcessorEx(long ptr ptr)
-# @ stub SetThreadInformation
+@ stdcall SetThreadInformation(long long ptr long)
@ stdcall SetThreadLocale(long)
@ stdcall SetThreadPreferredUILanguages(long ptr ptr)
@ stdcall SetThreadPriority(long long)
diff --git a/wine/dlls/kernelbase/memory.c b/wine/dlls/kernelbase/memory.c
index e5ad1e5ad..83a40a7cd 100644
--- a/wine/dlls/kernelbase/memory.c
+++ b/wine/dlls/kernelbase/memory.c
@@ -49,6 +49,19 @@ WINE_DECLARE_DEBUG_CHANNEL(globalmem);
***********************************************************************/


+/***********************************************************************
+ *             DiscardVirtualMemory   (kernelbase.@)
+ */
+DWORD WINAPI DECLSPEC_HOTPATCH DiscardVirtualMemory( void *addr, SIZE_T size )
+    NTSTATUS status;
+    LPVOID ret = addr;
+    status = NtAllocateVirtualMemory( GetCurrentProcess(), &ret, 0, &size, MEM_RESET, PAGE_NOACCESS );
+    return RtlNtStatusToDosError( status );
/***********************************************************************
*             FlushViewOfFile   (kernelbase.@)
*/
@@ -1286,6 +1299,23 @@ LPVOID WINAPI DECLSPEC_HOTPATCH VirtualAllocExNuma( HANDLE process, void *addr,
}


+/***********************************************************************
+ *             QueryVirtualMemoryInformation   (kernelbase.@)
+ */
+BOOL WINAPI DECLSPEC_HOTPATCH QueryVirtualMemoryInformation( HANDLE process, const void *addr,
+        WIN32_MEMORY_INFORMATION_CLASS info_class, void *info, SIZE_T size, SIZE_T *ret_size)
+    switch (info_class)
+        case MemoryRegionInfo:
+            return set_ntstatus( NtQueryVirtualMemory( process, addr, MemoryRegionInformation, info, size, ret_size ));
+        default:
+            FIXME("Unsupported info class %u.\n", info_class);
+            return FALSE;
/***********************************************************************
* CPU functions
***********************************************************************/
diff --git a/wine/dlls/kernelbase/thread.c b/wine/dlls/kernelbase/thread.c
index 1c878474a..3f61ae467 100644
--- a/wine/dlls/kernelbase/thread.c
+++ b/wine/dlls/kernelbase/thread.c
@@ -606,6 +606,25 @@ LANGID WINAPI DECLSPEC_HOTPATCH SetThreadUILanguage( LANGID langid )
}


+/**********************************************************************
+ *            SetThreadInformation   (kernelbase.@)
+ */
+BOOL WINAPI DECLSPEC_HOTPATCH SetThreadInformation( HANDLE thread, THREAD_INFORMATION_CLASS info_class,
+        VOID *info, DWORD size )
+    switch (info_class)
+    {
+        case ThreadMemoryPriority:
+            return set_ntstatus( NtSetInformationThread( thread, ThreadPagePriority, info, size ));
+        case ThreadPowerThrottling:
+            return set_ntstatus( NtSetInformationThread( thread, ThreadPowerThrottlingState, info, size ));
+        default:
+            FIXME("Unsupported class %u.\n", info_class);
+            return FALSE;
+    }
/**********************************************************************
*           SuspendThread   (kernelbase.@)
*/
diff --git a/wine/dlls/mfmediaengine/Makefile.in b/wine/dlls/mfmediaengine/Makefile.in
index a0e944c06..bd273aafd 100644
--- a/wine/dlls/mfmediaengine/Makefile.in
+++ b/wine/dlls/mfmediaengine/Makefile.in
MODULE    = mfmediaengine.dll
IMPORTS = oleaut32 ole32 mfplat mf mfuuid dxguid uuid

EXTRADLLFLAGS = -Wb,--prefer-native
diff --git a/wine/dlls/mfmediaengine/main.c b/wine/dlls/mfmediaengine/main.c
index a191448b6..98504c5e2 100644
--- a/wine/dlls/mfmediaengine/main.c
+++ b/wine/dlls/mfmediaengine/main.c
#include "mferror.h"
#include "dxgi.h"
#include "d3d11.h"

#include "wine/debug.h"


struct media_engine
{
          LONGLONG pts;
          SIZE size;
          if (FAILED(hr = IMFDXGIDeviceManager_OpenDeviceHandle(engine->device_manager, &engine->device_handle)))
          {
               return hr;
          }

          if (FAILED(hr = IMFDXGIDeviceManager_OpenDeviceHandle(engine->device_manager, &engine->device_handle)))
          {
               return hr;
          }
          hr = IMFDXGIDeviceManager_LockDevice(engine->device_manager, engine->device_handle, &IID_ID3D11Device,

          goto failed;


          goto failed;


          goto failed;

               NULL, &engine->video_frame.d3d11.srv)))
          goto failed;


          goto failed;

               &engine->video_frame.d3d11.input_layout)))
          goto failed;

          goto failed;

          goto failed;



}


          free(me);
{





}


{


          return E_INVALIDARG;
{


          return E_INVALIDARG;
static HRESULT WINAPI time_range_AddRange(IMFMediaTimeRange *iface, double start, double end)
{



          engine->flags &= ~mask;
}

{
}

static struct media_engine *impl_from_session_events_IMFAsyncCallback(IMFAsyncCallback *iface)
          return;

static ULONG WINAPI media_engine_session_events_AddRef(IMFAsyncCallback *iface)
{
}

static ULONG WINAPI media_engine_session_events_Release(IMFAsyncCallback *iface)
{
}

static HRESULT WINAPI media_engine_callback_GetParameters(IMFAsyncCallback *iface, DWORD *flags, DWORD *queue)

          goto failed;

          goto failed;

          IMFMediaEvent_Release(event);


}
static ULONG WINAPI media_engine_load_handler_AddRef(IMFAsyncCallback *iface)
{
}

static ULONG WINAPI media_engine_load_handler_Release(IMFAsyncCallback *iface)
{
}

static HRESULT media_engine_create_source_node(IMFMediaSource *source, IMFPresentationDescriptor *pd, IMFStreamDescriptor *sd,
}

static HRESULT media_engine_create_topology(struct media_engine *engine, IMFMediaSource *source)
{


          return hr;




               IMFMediaTypeHandler_Release(type_handler);
          }

          return E_UNEXPECTED;


          IMFTopologyNode *sar_node = NULL, *audio_src = NULL;
          IMFTopologyNode *grabber_node = NULL, *video_src = NULL;

          if (sd_audio)
          {
               if (FAILED(hr = media_engine_create_source_node(source, pd, sd_audio, &audio_src)))

               if (FAILED(hr = media_engine_create_audio_renderer(engine, &sar_node)))

               if (sar_node && audio_src)
               {
          if (SUCCEEDED(hr) && sd_video)
          {
               if (FAILED(hr = media_engine_create_source_node(source, pd, sd_video, &video_src)))

               if (FAILED(hr = media_engine_create_video_renderer(engine, &grabber_node)))

               if (grabber_node && video_src)
               {
static HRESULT WINAPI media_engine_load_handler_Invoke(IMFAsyncCallback *iface, IMFAsyncResult *result)
{



};

{

          IsEqualIID(riid, &IID_IUnknown))
          *obj = iface;

}

{


}
          IMFSourceResolver_Release(engine->resolver);
          IMFDXGIDeviceManager_CloseDeviceHandle(engine->device_manager, engine->device_handle);
}

{


          free_media_engine(engine);
}

{

}

{

}

{

}

{












}

{


          if (!(*url = SysAllocString(engine->current_source)))
               hr = E_OUTOFMEMORY;

}

{


}

{

}

{


}

{

          return hr;

          hr = IMFMediaTimeRange_AddRange(*range, 0.0, engine->duration);

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{


}

{

}

{


}

{








}

{






}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

}

{

          media_engine_set_flag(engine, FLAGS_ENGINE_SHUT_DOWN, TRUE);
          IMFMediaSession_Shutdown(engine->session);

          goto done;


          goto done;

}

          const MFVideoNormalizedRect *src_rect, const RECT *dst_rect, const MFARGB *color)
{

}

{

}

{
};

static HRESULT WINAPI media_engine_grabber_callback_QueryInterface(IMFSampleGrabberSinkCallback *iface,
static ULONG WINAPI media_engine_grabber_callback_AddRef(IMFSampleGrabberSinkCallback *iface)
{
}

static ULONG WINAPI media_engine_grabber_callback_Release(IMFSampleGrabberSinkCallback *iface)
{
}

static HRESULT WINAPI media_engine_grabber_callback_OnClockStart(IMFSampleGrabberSinkCallback *iface,

          return hr;



          return E_POINTER;
          return hr;


}
diff --git a/wine/dlls/mfmediaengine/tests/Makefile.in b/wine/dlls/mfmediaengine/tests/Makefile.in
index 421b75587..13bbef64d 100644
--- a/wine/dlls/mfmediaengine/tests/Makefile.in
+++ b/wine/dlls/mfmediaengine/tests/Makefile.in
TESTDLL   = mfmediaengine.dll

C_SRCS = \
     mfmediaengine.c
diff --git a/wine/dlls/mfmediaengine/tests/mfmediaengine.c b/wine/dlls/mfmediaengine/tests/mfmediaengine.c
index 008ee5884..096f6e3f2 100644
--- a/wine/dlls/mfmediaengine/tests/mfmediaengine.c
+++ b/wine/dlls/mfmediaengine/tests/mfmediaengine.c
#include "mferror.h"
#include "dxgi.h"
#include "initguid.h"

#include "wine/test.h"

static HRESULT (WINAPI *pMFCreateDXGIDeviceManager)(UINT *token, IMFDXGIDeviceManager **manager);
}

static void init_functions(void)
static ULONG WINAPI media_engine_notify_Release(IMFMediaEngineNotify *iface)
{
}

static HRESULT WINAPI media_engine_notify_EventNotify(IMFMediaEngineNotify *iface, DWORD event, DWORD_PTR param1, DWORD param2)
};

static IMFMediaEngine *create_media_engine(IMFMediaEngineNotify *callback)
{





}

static void test_factory(void)
{

               (void **)&factory);
          win_skip("Media Engine is not supported.\n");
          return;

               &IID_IMFMediaEngineClassFactory, (void **)&factory2);





}

static void test_CreateInstance(void)
{



               attributes, &media_engine);


               attributes, &media_engine);




}

static void test_Shutdown(void)
{


































