#!/bin/sh
# Fix GCC build issues on macOS (especially ARM64)

SOURCE_DIR=$1

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 <source_directory>"
    exit 1
fi

ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" != "Darwin" ]; then
    echo "Skipping GCC macOS fixes (not macOS)"
    exit 0
fi

echo "Applying GCC macOS fixes in $SOURCE_DIR"

# Fix 1: Fix zlib fdopen macro conflict on macOS (affects all macOS)
echo "Fixing zlib fdopen macro for macOS..."
if [ -f "$SOURCE_DIR/zlib/zutil.h" ]; then
    # Apply zlib fdopen fix as a patch
    cat > /tmp/zlib_fdopen_fix.patch << 'EOF'
--- a/zlib/zutil.h
+++ b/zlib/zutil.h
@@ -133,12 +133,3 @@
 #if defined(MACOS) || defined(TARGET_OS_MAC)
 #  define OS_CODE  7
-#  ifndef Z_SOLO
-#    if defined(__MWERKS__) && __dest_os != __be_os && __dest_os != __win32_os
-#      include <unix.h> /* for fdopen */
-#    else
-#      ifndef fdopen
-#        define fdopen(fd,mode) NULL /* No fdopen() */
-#      endif
-#    endif
-#  endif
 #endif
EOF
    patch -d "$SOURCE_DIR" -p1 -t -N < /tmp/zlib_fdopen_fix.patch || echo "Warning: zlib fdopen patch may have already been applied"
    rm -f /tmp/zlib_fdopen_fix.patch
fi

# ARM64-specific fixes
if [ "$ARCH" = "arm64" ]; then
    echo "Applying ARM64-specific fixes..."
    
    # Fix 2: Fix safe-ctype.h conflicts with C++ standard library headers
    echo "Fixing safe-ctype.h conflicts with C++ headers..."
    if [ -f "$SOURCE_DIR/include/safe-ctype.h" ]; then
        # Wrap the macro redefinitions in #ifndef __cplusplus
        # Add #ifndef __cplusplus before the #undef isalpha line
        sed -i '' '/^#undef isalpha$/i\
#ifndef __cplusplus
' "$SOURCE_DIR/include/safe-ctype.h"
        
        # Add #endif before the final #endif /* SAFE_CTYPE_H */
        sed -i '' '/^#endif \/\* SAFE_CTYPE_H \*\/$/i\
#endif /* __cplusplus */
' "$SOURCE_DIR/include/safe-ctype.h"
    fi
    
    # Fix 3: Remove -no-pie flags that cause issues on macOS ARM64
    echo "Removing -no-pie flags from configure scripts..."
    find "$SOURCE_DIR" -name "configure" -type f -exec sed -i '' 's/-no-pie//g' {} +
    
    # Fix 4: Ensure host-darwin.c is compiled for ARM64
    echo "Checking host-darwin configuration..."
    if [ -f "$SOURCE_DIR/gcc/config.host" ]; then
        # First, remove any broken aarch64-darwin line from previous attempts
        sed -i '' '/^  aarch64-\*-darwin\* | arm64-\*-darwin\*)$/d' "$SOURCE_DIR/gcc/config.host"
        
        # Now add aarch64-darwin to the x86_64-darwin case if not already there
        if ! grep "i\[34567\]86-\*-darwin\* | x86_64-\*-darwin\*.*aarch64" "$SOURCE_DIR/gcc/config.host" > /dev/null 2>&1; then
            echo "Adding aarch64-darwin to x86_64-darwin case..."
            # Add aarch64 to the existing x86_64-darwin pattern
            sed -i '' 's/i\[34567\]86-\*-darwin\* | x86_64-\*-darwin\*)/i[34567]86-*-darwin* | x86_64-*-darwin* | aarch64-*-darwin* | arm64-*-darwin*)/' "$SOURCE_DIR/gcc/config.host"
        fi
    fi
fi

echo "GCC ARM64 macOS fixes applied"
exit 0

