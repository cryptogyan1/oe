#!/bin/bash
# Polymarket Bot - 401 Unauthorized Fix (v3) Installer

set -e

echo "🔧 Polymarket Bot - Authentication Fix v3"
echo "=========================================="
echo ""
echo "This fix adds authentication to order submissions"
echo "to resolve 401 Unauthorized errors."
echo ""

# Check if we're in the right directory
if [ ! -f "Cargo.toml" ]; then
    echo "❌ Error: Cargo.toml not found!"
    echo "   Please run this script from your bot's root directory"
    exit 1
fi

# Backup the original files
echo "📋 Creating backups..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp src/execution/clob_client.rs "src/execution/clob_client.rs.backup.$TIMESTAMP"
cp src/main.rs "src/main.rs.backup.$TIMESTAMP"
cp src/bin/diagnostics.rs "src/bin/diagnostics.rs.backup.$TIMESTAMP"
echo "✅ Backups created:"
echo "   - src/execution/clob_client.rs.backup.$TIMESTAMP"
echo "   - src/main.rs.backup.$TIMESTAMP"
echo "   - src/bin/diagnostics.rs.backup.$TIMESTAMP"
echo ""

# Extract fixed files
if [ -f "polymarket_bot_fixed_v3.tar.gz" ]; then
    echo "📦 Extracting fixed files from archive..."
    tar -xzf polymarket_bot_fixed_v3.tar.gz \
        src/execution/clob_client.rs \
        src/main.rs \
        src/bin/diagnostics.rs
    echo "✅ Files extracted successfully!"
else
    echo "❌ polymarket_bot_fixed_v3.tar.gz not found"
    echo "   Please ensure the archive is in the current directory"
    exit 1
fi

echo ""
echo "🏗️  Rebuilding bot..."
if cargo build --release; then
    echo "✅ Build successful!"
else
    echo "❌ Build failed - please check the error messages above"
    echo ""
    echo "🔄 To restore backups:"
    echo "   cp src/execution/clob_client.rs.backup.$TIMESTAMP src/execution/clob_client.rs"
    echo "   cp src/main.rs.backup.$TIMESTAMP src/main.rs"
    echo "   cp src/bin/diagnostics.rs.backup.$TIMESTAMP src/bin/diagnostics.rs"
    exit 1
fi

echo ""
echo "✨ Fix applied successfully!"
echo ""
echo "📝 What changed:"
echo "   ✅ ClobClient now has API credentials"
echo "   ✅ Order submissions include authentication headers"
echo "   ✅ Uses HMAC-SHA256 signing (same as diagnostics)"
echo ""
echo "🧪 To test the fix:"
echo "   RUST_LOG=info cargo run"
echo ""
echo "✅ You should now see:"
echo "   📤 Submitting order to CLOB API..."
echo "   ✅ Order submitted! ID: ..."
echo ""
echo "❌ Instead of:"
echo "   ❌ Order rejected by CLOB API"
echo "   Status: 401 Unauthorized"
echo ""
echo "📚 For more details, see FIX_SUMMARY_V3.md"
echo ""
