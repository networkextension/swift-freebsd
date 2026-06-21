--- swift-testing/Sources/Testing/Support/Locked.swift.orig
+++ swift-testing/Sources/Testing/Support/Locked.swift
@@ -28,7 +28,7 @@
   /// A type providing storage for the underlying lock and wrapped value.
 #if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
   private typealias _Storage = ManagedBuffer<T, os_unfair_lock_s>
-#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
+#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android) || os(FreeBSD))
   private final class _Storage: ManagedBuffer<T, pthread_mutex_t> {
     deinit {
       withUnsafeMutablePointerToElements { lock in
@@ -61,7 +61,7 @@
     _storage.withUnsafeMutablePointerToElements { lock in
       lock.initialize(to: .init())
     }
-#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
+#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android) || os(FreeBSD))
     _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in rawValue }) as! _Storage
     _storage.withUnsafeMutablePointerToElements { lock in
       _ = pthread_mutex_init(lock, nil)
@@ -105,7 +105,7 @@
       }
       return try body(&rawValue.pointee)
     }
-#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
+#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android) || os(FreeBSD))
      result = try _storage.withUnsafeMutablePointers { rawValue, lock in
       pthread_mutex_lock(lock)
       defer {
@@ -148,7 +148,7 @@
       }
       return try body(&rawValue.pointee)
     }
-#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
+#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android) || os(FreeBSD))
     result = try _storage.withUnsafeMutablePointers { rawValue, lock in
       guard 0 == pthread_mutex_trylock(lock) else {
         return nil
