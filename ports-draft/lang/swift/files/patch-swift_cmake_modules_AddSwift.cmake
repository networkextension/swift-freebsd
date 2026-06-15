--- swift/cmake/modules/AddSwift.cmake.orig
+++ swift/cmake/modules/AddSwift.cmake
@@ -587,8 +587,8 @@ function(_add_swift_runtime_link_flags target relpath_to_lib_dir bootstrapping)
       target_link_libraries(${target} PRIVATE ${swiftrt})
       target_link_libraries(${target} PRIVATE "swiftCore")

-      target_link_directories(${target} PRIVATE ${host_lib_dir})
       target_link_directories(${target} PRIVATE ${host_lib_arch_dir})
+      target_link_directories(${target} PRIVATE ${host_lib_dir})

       # At runtime, use swiftCore in the current toolchain.
       # For building stdlib, LD_LIBRARY_PATH will be set to builder's stdlib
