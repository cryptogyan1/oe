#!/bin/bash

set -e  # Exit on error

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   POLYMARKET ARBITRAGE BOT - COMPLETE FIX${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

# ===== STEP 1: Check Prerequisites =====
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 not found. Please install Python 3.8+${NC}"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo -e "${RED}❌ Rust/Cargo not found. Please install from https://rustup.rs${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo -e "${GREEN}✅ Python ${PYTHON_VERSION} found${NC}"
echo -e "${GREEN}✅ Rust/Cargo found${NC}"

# ===== STEP 2: Setup Python Environment =====
echo ""
echo -e "${YELLOW}[2/6] Setting up Python environment...${NC}"

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✅ Virtual environment created${NC}"
else
    echo -e "${GREEN}✅ Virtual environment already exists${NC}"
fi

source venv/bin/activate

pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt

echo -e "${GREEN}✅ Python dependencies installed${NC}"

# ===== STEP 3: Setup Environment File =====
echo ""
echo -e "${YELLOW}[3/6] Setting up environment file...${NC}"

if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env file already exists${NC}"
    echo -n "Do you want to keep it? (y/N): "
    read -r KEEP_ENV
    if [[ ! $KEEP_ENV =~ ^[Yy]$ ]]; then
        cp .env.template .env
        echo -e "${GREEN}✅ New .env created from template${NC}"
    else
        echo -e "${GREEN}✅ Keeping existing .env${NC}"
    fi
else
    cp .env.template .env
    echo -e "${GREEN}✅ .env created from template${NC}"
fi

# ===== STEP 4: Update Rust Client =====
echo ""
echo -e "${YELLOW}[4/6] Updating Rust client code...${NC}"

# Find the bot directory
if [ -d "../bigb-main-improved" ]; then
    BOT_DIR="../bigb-main-improved"
elif [ -d "bigb-main-improved" ]; then
    BOT_DIR="bigb-main-improved"
else
    echo -e "${RED}❌ Could not find bigb-main-improved directory${NC}"
    echo "Please run this script from the correct location"
    exit 1
fi

# Backup old file
if [ -f "$BOT_DIR/src/execution/clob_client.rs" ]; then
    cp "$BOT_DIR/src/execution/clob_client.rs" "$BOT_DIR/src/execution/clob_client.rs.backup"
    echo -e "${GREEN}✅ Backed up old clob_client.rs${NC}"
fi

# Copy new file
cp clob_client_fixed.rs "$BOT_DIR/src/execution/clob_client.rs"
echo -e "${GREEN}✅ Updated clob_client.rs${NC}"

# Update Cargo.toml to remove HMAC dependencies
echo -e "${YELLOW}   Updating Cargo.toml...${NC}"
# Remove hmac, sha2, base64 dependencies
sed -i.backup '/^hmac = /d' "$BOT_DIR/Cargo.toml"
sed -i '/^sha2 = /d' "$BOT_DIR/Cargo.toml"
sed -i '/^base64 = /d' "$BOT_DIR/Cargo.toml"
echo -e "${GREEN}✅ Removed manual HMAC dependencies${NC}"

# ===== STEP 5: Build Rust Bot =====
echo ""
echo -e "${YELLOW}[5/6] Building Rust bot...${NC}"

cd "$BOT_DIR"
cargo build --release
cd - > /dev/null

echo -e "${GREEN}✅ Rust bot compiled${NC}"

# ===== STEP 6: Configuration Instructions =====
echo ""
echo -e "${YELLOW}[6/6] Configuration${NC}"
echo ""

# Check if .env is configured
if grep -q "your_private_key_here" .env 2>/dev/null; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  IMPORTANT: You MUST configure your .env file!${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "1. Edit the .env file:"
    echo "   nano .env"
    echo ""
    echo "2. Set these REQUIRED values:"
    echo "   - PRIVATE_KEY (without 0x prefix)"
    echo "   - PROXY_WALLET (with 0x prefix)"
    echo ""
    echo "3. Optional: Get Polymarket API credentials from:"
    echo "   https://clob.polymarket.com/ → Settings → API"
    echo "   (If not set, bot will generate new ones)"
    echo ""
    echo "4. Test your configuration:"
    echo "   ./test_credentials.sh"
    echo ""
    echo "5. Start the bot:"
    echo "   ./start_bot.sh"
    echo ""
else
    echo -e "${GREEN}✅ .env file appears to be configured${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Test credentials: ./test_credentials.sh"
    echo "2. Start the bot: ./start_bot.sh"
    echo ""
fi

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""
