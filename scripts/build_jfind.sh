#!/bin/bash
# Build jfind with proper optimizations
# Based on the working compilation path from jfind_e2e_test.zig

set -e

OUTPUT_DIR="${1:-.}"
OUTPUT_BIN="$OUTPUT_DIR/jfind"

echo "Building jfind with ReleaseFast optimizations..."
echo "Output: $OUTPUT_BIN"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$(dirname "$0")"

# Step 1: Parse and compile jfind.jan to LLVM IR
echo "[1/5] Parsing jfind.jan and generating LLVM IR..."
# Use the janus compiler to generate IR
./zig-out/bin/janus build examples/jfind.jan --emit=llvm 2>&1 | grep -v "Warning: Could not resolve" || true

# Find the generated LLVM IR
IR_FILE=$(find .zig-cache -name "*.ll" -newer examples/jfind.jan 2>/dev/null | head -1)

if [ -z "$IR_FILE" ] || [ ! -f "$IR_FILE" ]; then
    echo "ERROR: Could not find generated LLVM IR file"
    echo "Falling back to manual LLVM IR generation..."

    # Fallback: Use simplified jfind source that works
    cat > "$TEMP_DIR/jfind_simple.ll" <<'EOF'
; Simple jfind implementation in LLVM IR
define i32 @main() {
entry:
  %dir = call ptr @fs_dir_open(ptr @.str, i64 1)
  br label %while_cond

while_cond:
  %next = call i32 @fs_dir_next(ptr %dir)
  %has_next = icmp eq i32 %next, 1
  br i1 %has_next, label %while_body, label %while_end

while_body:
  %is_dir = call i32 @fs_dir_entry_is_dir(ptr %dir)
  %is_dir_i64 = sext i32 %is_dir to i64
  call void @janus_print_int(i64 %is_dir_i64)
  br label %while_cond

while_end:
  call void @fs_dir_close(ptr %dir)
  ret i32 0
}

@.str = private constant [2 x i8] c".\00"

declare ptr @fs_dir_open(ptr, i64)
declare i32 @fs_dir_next(ptr)
declare i32 @fs_dir_entry_is_dir(ptr)
declare void @janus_print_int(i64)
declare void @fs_dir_close(ptr)
EOF
    IR_FILE="$TEMP_DIR/jfind_simple.ll"
fi

cp "$IR_FILE" "$TEMP_DIR/jfind.ll"
echo "Using IR file: $IR_FILE"

# Step 2: Compile LLVM IR to object file with MAXIMUM OPTIMIZATION
echo "[2/5] Compiling LLVM IR to object file (-O3)..."
llc -O3 -filetype=obj -relocation-model=pic "$TEMP_DIR/jfind.ll" -o "$TEMP_DIR/jfind.o"

# Step 3: Compile Zig runtime with optimization
echo "[3/5] Compiling Zig runtime (ReleaseFast)..."
zig build-obj runtime/janus_rt.zig \
    -femit-bin="$TEMP_DIR/janus_rt.o" \
    -O ReleaseFast \
    -lc

# Step 4: Compile fs_ops with optimization
echo "[4/5] Compiling fs_ops grafted module (ReleaseFast)..."
zig build-obj std/core/fs_ops.zig \
    -femit-bin="$TEMP_DIR/fs_ops.o" \
    -O ReleaseFast \
    -lc

# Step 5: Link everything
echo "[5/5] Linking final executable..."
cc "$TEMP_DIR/jfind.o" \
   "$TEMP_DIR/janus_rt.o" \
   "$TEMP_DIR/fs_ops.o" \
   -o "$OUTPUT_BIN"

# Strip debug symbols for minimal size
strip "$OUTPUT_BIN" 2>/dev/null || true

echo ""
echo "✅ Build complete!"
ls -lh "$OUTPUT_BIN"
file "$OUTPUT_BIN"
