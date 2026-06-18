--- swift/lib/Macros/Sources/SwiftMacros/DebugDescriptionMacro.swift.orig
+++ swift/lib/Macros/Sources/SwiftMacros/DebugDescriptionMacro.swift
@@ -541,7 +541,7 @@ extension String {
       return result
     }

-    return self.replacing("$", with: "\\$")
+    return String(self.flatMap { $0 == "$" ? Array("\\$") : [$0] })
   }
 }

