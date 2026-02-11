#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   STARTING POLYMARKET ARBITRAGE BOT${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

# Check .env file
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Run ./setup.sh first"
    exit 1
fi

# Load .env
export $(cat .env | grep -v '^#' | xargs)

# Check if configured
if [[ "$PRIVATE_KEY" == "your_private_key_here"* ]]; then
    echo -e "${RED}❌ .env file not configured!${NC}"
    echo "Please edit .env file with your credentials"
    echo "Then run: ./test_credentials.sh"
    exit 1
fi

# Find bot directory
if [ -d "../bigb-main-improved" ]; then
    BOT_DIR="../bigb-main-improved"
elif [ -d "bigb-main-improved" ]; then
    BOT_DIR="bigb-main-improved"
else
    echo -e "${RED}❌ Could not find bigb-main-improved directory${NC}"
    exit 1
fi

# Check if bot is built
if [ ! -f "$BOT_DIR/target/release/polymarket-15m-arbitrage-bot" ]; then
    echo -e "${YELLOW}⚠️  Bot not built. Building now...${NC}"
    cd "$BOT_DIR"
    cargo build --release
    cd - > /dev/null
fi

# Trap to kill both processes on exit
trap 'kill $(jobs -p) 2>/dev/null; echo -e "\n${YELLOW}Shutting down...${NC}"; exit' INT TERM

echo -e "${GREEN}[1/2] Starting Python Executor...${NC}"
echo ""

# Start Python executor in background
if [ -d "venv" ]; then
    source venv/bin/activate
fi

python3 python_executor.py &
PYTHON_PID=$!

# Wait for Python to start
sleep 3

# Check if Python is still running
if ! kill -0 $PYTHON_PID 2>/dev/null; then
    echo -e "${RED}❌ Python executor failed to start!${NC}"
    echo "Check the error messages above"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Python Executor running (PID: $PYTHON_PID)${NC}"
echo -e "   Listening on http://localhost:${EXECUTOR_PORT:-8765}"
echo ""

sleep 2

echo -e "${GREEN}[2/2] Starting Rust Core Engine...${NC}"
echo ""

cd "$BOT_DIR"

# Set environment for Rust
export RUST_LOG=${RUST_LOG:-info}

# Start Rust bot
cargo run --release

# If we get here, bot stopped
echo -e "${YELLOW}Bot stopped${NC}"
kill $PYTHON_PID 2>/dev/null
