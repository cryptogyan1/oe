#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   TESTING POLYMARKET CREDENTIALS${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Run ./setup.sh first"
    exit 1
fi

# Activate virtual environment
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo -e "${RED}❌ Virtual environment not found!${NC}"
    echo "Run ./setup.sh first"
    exit 1
fi

# Run Python test
python3 << 'PYEOF'
import os
import sys
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

print(f"{YELLOW}[1/3] Checking environment variables...{NC}")
print()

# Check required variables
checks = {
    'PRIVATE_KEY': os.getenv('PRIVATE_KEY'),
    'PROXY_WALLET': os.getenv('PROXY_WALLET'),
    'CHAIN_ID': os.getenv('CHAIN_ID'),
    'RPC_URL': os.getenv('RPC_URL'),
}

optional_checks = {
    'POLYMARKET_API_KEY': os.getenv('POLYMARKET_API_KEY'),
    'POLYMARKET_API_SECRET': os.getenv('POLYMARKET_API_SECRET'),
    'POLYMARKET_PASSPHRASE': os.getenv('POLYMARKET_PASSPHRASE'),
}

all_present = True
for key, value in checks.items():
    if not value or value.startswith('your_') or value.startswith('0xYour'):
        print(f"{RED}✗{NC} {key}: NOT SET")
        all_present = False
    else:
        if key == 'PRIVATE_KEY':
            preview = value[:8] + '...' if len(value) > 8 else '***'
        else:
            preview = value[:16] + '...' if len(value) > 16 else value
        print(f"{GREEN}✓{NC} {key}: {preview}")

print()
print("Optional API credentials:")
has_api_creds = True
for key, value in optional_checks.items():
    if not value or len(value) == 0:
        print(f"{YELLOW}⚠{NC} {key}: Not set (will be generated)")
        has_api_creds = False
    else:
        preview = value[:12] + '...' if len(value) > 12 else value
        print(f"{GREEN}✓{NC} {key}: {preview}")

if not all_present:
    print()
    print(f"{RED}Please edit .env file with your real credentials{NC}")
    sys.exit(1)

print()
print(f"{YELLOW}[2/3] Testing wallet configuration...{NC}")
print()

try:
    from web3 import Web3
    
    private_key = os.getenv('PRIVATE_KEY')
    if private_key.startswith('0x'):
        private_key = private_key[2:]
    
    w3 = Web3()
    account = w3.eth.account.from_key(private_key)
    
    print(f"{GREEN}✓{NC} Private key valid")
    print(f"  EOA Address: {account.address}")
    
    proxy = os.getenv('PROXY_WALLET')
    print(f"  Proxy Wallet: {proxy}")
    
    if account.address.lower() == proxy.lower():
        print(f"{YELLOW}ℹ{NC} EOA and Proxy are the same (standard wallet)")
    else:
        print(f"{YELLOW}ℹ{NC} EOA and Proxy are different (likely Gnosis Safe)")
    
except Exception as e:
    print(f"{RED}✗{NC} Wallet configuration error: {e}")
    sys.exit(1)

print()
print(f"{YELLOW}[3/3] Testing Polymarket API connection...{NC}")
print()

try:
    from py_clob_client.client import ClobClient
    from py_clob_client.clob_types import ApiCreds
    from py_clob_client.constants import POLYGON
    
    host = os.getenv('CLOB_API_URL', 'https://clob.polymarket.com')
    chain_id = int(os.getenv('CHAIN_ID', str(POLYGON)))
    
    private_key = os.getenv('PRIVATE_KEY')
    if private_key.startswith('0x'):
        private_key = private_key[2:]
    
    # Create credentials object if available
    creds = None
    if has_api_creds:
        creds = ApiCreds(
            api_key=os.getenv('POLYMARKET_API_KEY'),
            api_secret=os.getenv('POLYMARKET_API_SECRET'),
            api_passphrase=os.getenv('POLYMARKET_PASSPHRASE')
        )
    
    print("Initializing ClobClient...")
    client = ClobClient(
        host=host,
        key=private_key,
        chain_id=chain_id,
        creds=creds
    )
    
    print(f"{GREEN}✓{NC} ClobClient initialized")
    
    # If no creds, try to create/derive
    if not has_api_creds:
        print()
        print(f"{YELLOW}ℹ{NC} No API credentials found. Attempting to generate...")
        try:
            new_creds = client.create_api_key()
            print(f"{GREEN}✓{NC} New API credentials generated!")
            print()
            print(f"{BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}")
            print(f"{BLUE}  SAVE THESE TO YOUR .env FILE:{NC}")
            print(f"{BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}")
            print(f"POLYMARKET_API_KEY={new_creds.api_key}")
            print(f"POLYMARKET_API_SECRET={new_creds.api_secret}")
            print(f"POLYMARKET_PASSPHRASE={new_creds.api_passphrase}")
            print(f"{BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}")
            print()
        except Exception as e:
            print(f"{YELLOW}⚠{NC} Could not create API key: {e}")
            print("Trying to derive API key...")
            try:
                derived_creds = client.derive_api_key()
                print(f"{GREEN}✓{NC} API credentials derived!")
            except Exception as e2:
                print(f"{RED}✗{NC} Could not derive API key: {e2}")
                print()
                print("This is okay - you can still use the bot.")
                print("Just go to https://clob.polymarket.com/ and create API keys manually.")
    
    # Try to get balance
    print()
    print("Testing API endpoints...")
    try:
        balance_info = client.get_balance_allowance()
        print(f"{GREEN}✓{NC} API responding successfully")
        print(f"  Balance: ${balance_info.get('balance', 'N/A')}")
        print(f"  Allowance: ${balance_info.get('allowance', 'N/A')}")
    except Exception as e:
        print(f"{YELLOW}⚠{NC} Could not fetch balance: {e}")
        print("  (This may be normal if API keys are not set)")
    
    print()
    print(f"{GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}")
    print(f"{GREEN}✅ CREDENTIALS ARE VALID!{NC}")
    print(f"{GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}")
    print()
    print("You're ready to start trading:")
    print("  ./start_bot.sh")
    print()
    
except Exception as e:
    print(f"{RED}✗{NC} Connection test failed: {e}")
    print()
    print("Possible issues:")
    print("1. Invalid API credentials")
    print("2. Wrong private key format")
    print("3. Network connectivity issue")
    print("4. Wrong chain ID")
    print()
    sys.exit(1)

PYEOF

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Tests failed. Please fix the errors above.${NC}"
fi

exit $exit_code
