#!/usr/bin/env python3
"""
Python Order Executor for Polymarket
Uses official py-clob-client for proper authentication
Receives order requests from Rust bot via HTTP
"""

import os
import sys
import logging
from decimal import Decimal
from flask import Flask, request, jsonify
from dotenv import load_dotenv

# Import official py-clob-client
from py_clob_client.client import ClobClient
from py_clob_client.clob_types import ApiCreds, OrderArgs, OrderType
from py_clob_client.order_builder.constants import BUY, SELL
from py_clob_client.constants import POLYGON

# ===== CONFIGURATION =====

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ===== FLASK APP =====

app = Flask(__name__)

# ===== POLYMARKET CLIENT =====

class PolymarketExecutor:
    """Handles all Polymarket API interactions with proper authentication"""
    
    def __init__(self):
        # Get credentials from environment
        self.private_key = os.getenv('PRIVATE_KEY')
        self.api_key = os.getenv('POLYMARKET_API_KEY')
        self.api_secret = os.getenv('POLYMARKET_API_SECRET')
        self.api_passphrase = os.getenv('POLYMARKET_PASSPHRASE')
        self.chain_id = int(os.getenv('CHAIN_ID', str(POLYGON)))
        self.host = os.getenv('CLOB_API_URL', 'https://clob.polymarket.com')
        
        # Validate credentials
        if not self.private_key:
            raise ValueError("❌ PRIVATE_KEY not found in .env file")
        
        # Remove 0x prefix if present
        if self.private_key.startswith('0x'):
            self.private_key = self.private_key[2:]
        
        logger.info("🔧 Initializing Polymarket client...")
        logger.info(f"   Host: {self.host}")
        logger.info(f"   Chain ID: {self.chain_id}")
        logger.info(f"   API Key present: {bool(self.api_key)}")
        
        try:
            # Create API credentials object (optional for some operations)
            creds = None
            if all([self.api_key, self.api_secret, self.api_passphrase]):
                creds = ApiCreds(
                    api_key=self.api_key,
                    api_secret=self.api_secret,
                    api_passphrase=self.api_passphrase
                )
                logger.info("✅ API credentials configured")
            else:
                logger.warning("⚠️  No API credentials - will generate new ones")
            
            # Initialize the official ClobClient
            self.client = ClobClient(
                host=self.host,
                key=self.private_key,
                chain_id=self.chain_id,
                creds=creds
            )
            
            # If no creds, try to create/derive them
            if not creds:
                logger.info("🔑 Creating API credentials...")
                try:
                    new_creds = self.client.create_api_key()
                    logger.info("✅ New API key created!")
                    logger.info(f"   API Key: {new_creds.api_key}")
                    logger.info(f"   API Secret: {new_creds.api_secret}")
                    logger.info(f"   Passphrase: {new_creds.api_passphrase}")
                    logger.info("⚠️  SAVE THESE TO YOUR .ENV FILE!")
                    
                    # Reinitialize with new creds
                    self.client = ClobClient(
                        host=self.host,
                        key=self.private_key,
                        chain_id=self.chain_id,
                        creds=new_creds
                    )
                except Exception as e:
                    logger.warning(f"Could not create API key: {e}")
                    logger.info("Trying to derive API key instead...")
                    try:
                        derived_creds = self.client.derive_api_key()
                        logger.info("✅ API key derived!")
                        self.client = ClobClient(
                            host=self.host,
                            key=self.private_key,
                            chain_id=self.chain_id,
                            creds=derived_creds
                        )
                    except Exception as e2:
                        logger.error(f"Could not derive API key: {e2}")
            
            # Test connection
            try:
                balance_info = self.client.get_balance_allowance()
                logger.info(f"✅ Connected! Balance: ${balance_info.get('balance', 'N/A')}")
                logger.info(f"   Allowance: ${balance_info.get('allowance', 'N/A')}")
            except Exception as e:
                logger.warning(f"Could not fetch balance: {e}")
                logger.info("Client initialized but balance check failed (this may be normal)")
            
            logger.info("✅ Polymarket executor ready!")
            
        except Exception as e:
            logger.error(f"❌ Failed to initialize client: {e}")
            raise
    
    def place_order(self, order_data: dict) -> dict:
        """
        Place a single order using py-clob-client
        
        Args:
            order_data: {
                "token_id": "0x123...",
                "side": "BUY" or "SELL",
                "price": "0.50",
                "size": "10.0",
                "order_type": "FOK" or "GTC" or "GTD"
            }
        
        Returns:
            {"success": bool, "order_id": str, "error": str}
        """
        try:
            logger.info(f"📥 Placing {order_data['side']} order")
            logger.info(f"   Token: {order_data['token_id'][:16]}...")
            logger.info(f"   Price: ${order_data['price']} x {order_data['size']}")
            
            # Map side to py-clob-client constants
            side = BUY if order_data['side'].upper() == 'BUY' else SELL
            
            # Create order args
            order_args = OrderArgs(
                price=float(order_data['price']),
                size=float(order_data['size']),
                side=side,
                token_id=order_data['token_id']
            )
            
            # Create and sign the order
            signed_order = self.client.create_order(order_args)
            logger.info("✅ Order signed")
            
            # Map order type
            order_type_map = {
                'FOK': OrderType.FOK,
                'GTC': OrderType.GTC,
                'GTD': OrderType.GTD,
            }
            order_type = order_type_map.get(order_data.get('order_type', 'FOK'), OrderType.FOK)
            
            # Submit the order
            logger.info(f"📤 Submitting {order_type.name} order...")
            resp = self.client.post_order(signed_order, order_type=order_type)
            
            logger.info(f"✅ Order placed successfully!")
            logger.info(f"   Response: {resp}")
            
            return {
                'success': True,
                'order_id': resp.get('orderID', 'unknown'),
                'response': resp
            }
            
        except Exception as e:
            logger.error(f"❌ Order failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def execute_arbitrage(self, arb_data: dict) -> dict:
        """
        Execute atomic arbitrage orders
        
        Args:
            arb_data: {
                "buy_order": {...},
                "sell_order": {...},
                "arb_id": "..."
            }
        
        Returns:
            {"success": bool, "buy_result": {}, "sell_result": {}}
        """
        arb_id = arb_data.get('arb_id', 'unknown')
        logger.info(f"🎯 Executing arbitrage {arb_id}")
        
        results = {
            'arb_id': arb_id,
            'buy_result': None,
            'sell_result': None,
            'success': False,
            'error': None
        }
        
        try:
            # Execute BUY order first
            buy_result = self.place_order(arb_data['buy_order'])
            results['buy_result'] = buy_result
            
            if not buy_result['success']:
                logger.error(f"❌ BUY order failed: {buy_result.get('error')}")
                return results
            
            logger.info(f"✅ BUY order placed: {buy_result.get('order_id')}")
            
            # Execute SELL order
            sell_result = self.place_order(arb_data['sell_order'])
            results['sell_result'] = sell_result
            
            if not sell_result['success']:
                logger.error(f"❌ SELL order failed: {sell_result.get('error')}")
                logger.warning("⚠️  BUY succeeded but SELL failed - MANUAL INTERVENTION NEEDED")
                return results
            
            logger.info(f"✅ SELL order placed: {sell_result.get('order_id')}")
            
            results['success'] = True
            logger.info(f"🎉 Arbitrage {arb_id} completed successfully!")
            
        except Exception as e:
            logger.error(f"💥 Arbitrage execution error: {e}")
            results['error'] = str(e)
        
        return results
    
    def get_orderbook(self, token_id: str) -> dict:
        """Fetch orderbook for a token"""
        try:
            book = self.client.get_order_book(token_id)
            return {'success': True, 'orderbook': book}
        except Exception as e:
            logger.error(f"Failed to fetch orderbook: {e}")
            return {'success': False, 'error': str(e)}
    
    def cancel_order(self, order_id: str) -> dict:
        """Cancel a specific order"""
        try:
            self.client.cancel(order_id)
            logger.info(f"✅ Cancelled order {order_id}")
            return {'success': True}
        except Exception as e:
            logger.error(f"Failed to cancel order: {e}")
            return {'success': False, 'error': str(e)}

# ===== INITIALIZE EXECUTOR =====

try:
    executor = PolymarketExecutor()
except Exception as e:
    logger.error(f"❌ Failed to initialize executor: {e}")
    logger.error("Make sure your .env file is configured correctly!")
    sys.exit(1)

# ===== API ENDPOINTS =====

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'polymarket-executor',
        'version': '2.0.0'
    })

@app.route('/order', methods=['POST'])
def place_order():
    """
    Place a single order
    Body: {
        "token_id": "0x...",
        "side": "BUY"|"SELL",
        "price": "0.50",
        "size": "10",
        "order_type": "FOK"|"GTC"
    }
    """
    try:
        order_data = request.get_json()
        if not order_data:
            return jsonify({'error': 'No order data provided'}), 400
        
        result = executor.place_order(order_data)
        
        if result['success']:
            return jsonify(result), 200
        else:
            return jsonify(result), 500
            
    except Exception as e:
        logger.error(f"Error in /order endpoint: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/arbitrage', methods=['POST'])
def execute_arbitrage():
    """
    Execute arbitrage (buy + sell)
    Body: {
        "buy_order": {...},
        "sell_order": {...},
        "arb_id": "..."
    }
    """
    try:
        arb_data = request.get_json()
        if not arb_data:
            return jsonify({'error': 'No arbitrage data provided'}), 400
        
        result = executor.execute_arbitrage(arb_data)
        
        if result['success']:
            return jsonify(result), 200
        else:
            return jsonify(result), 500
            
    except Exception as e:
        logger.error(f"Error in /arbitrage endpoint: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/orderbook/<token_id>', methods=['GET'])
def get_orderbook(token_id: str):
    """Get orderbook for debugging"""
    result = executor.get_orderbook(token_id)
    if result['success']:
        return jsonify(result), 200
    else:
        return jsonify(result), 500

@app.route('/cancel/<order_id>', methods=['POST'])
def cancel_order(order_id: str):
    """Cancel an order"""
    result = executor.cancel_order(order_id)
    if result['success']:
        return jsonify(result), 200
    else:
        return jsonify(result), 500

# ===== RUN SERVER =====

if __name__ == '__main__':
    port = int(os.getenv('EXECUTOR_PORT', '8765'))
    logger.info("")
    logger.info("=" * 60)
    logger.info(f"🚀 Python Executor running on port {port}")
    logger.info(f"📡 Ready to receive orders from Rust bot")
    logger.info(f"   POST http://localhost:{port}/order - Place single order")
    logger.info(f"   POST http://localhost:{port}/arbitrage - Execute arbitrage")
    logger.info("=" * 60)
    logger.info("")
    
    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
