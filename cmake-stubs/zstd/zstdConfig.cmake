# Minimal zstd cmake config for FreeBSD cross-compile.
# Points zstd::libzstd_shared at the FreeBSD sysroot's libprivatezstd (same symbols).
cmake_minimum_required(VERSION 3.16)
if(NOT TARGET zstd::libzstd_shared)
  add_library(zstd::libzstd_shared SHARED IMPORTED GLOBAL)
  set_target_properties(zstd::libzstd_shared PROPERTIES
    IMPORTED_LOCATION /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.so
    INTERFACE_INCLUDE_DIRECTORIES /opt/freebsd15-aarch64-sysroot/usr/include)
endif()
if(NOT TARGET zstd::libzstd_static)
  add_library(zstd::libzstd_static STATIC IMPORTED GLOBAL)
  set_target_properties(zstd::libzstd_static PROPERTIES
    IMPORTED_LOCATION /opt/freebsd15-aarch64-sysroot/usr/lib/libzstd.a
    INTERFACE_INCLUDE_DIRECTORIES /opt/freebsd15-aarch64-sysroot/usr/include)
endif()
set(zstd_FOUND TRUE)
