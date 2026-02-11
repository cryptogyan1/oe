use anyhow::{anyhow, Result};
use ethers::prelude::*;
use ethers::types::{Address, U256};
use log::{info, warn};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::str::FromStr;
use std::sync::Arc;

// ==================================================
// CONSTANTS (Polygon / Polymarket)
// ==================================================

const POLYMARKET_EXCHANGE: &str = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E";
const CTF_CONTRACT: &str = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";
const USDC_ADDRESS: &str = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const MIN_ALLOWANCE: u128 = 1_000_000; // $1 (6 decimals)

// ==================================================
// CLIENT (DELEGATES TO PYTHON EXECUTOR)
// ==================================================

#[derive(Clone)]
pub struct ClobClient {
    pub http: Client,
    provider: Arc<SignerMiddleware<Provider<Http>, LocalWallet>>,
    proxy_wallet: Address,
    read_only: bool,
    // Python executor URL (no more manual API credentials!)
    python_executor_url: String,
}

impl ClobClient {
    pub async fn new(
        rpc_url: &str,
        private_key: &str,
        proxy_wallet: &str,
        _api_key: String,  // Kept for compatibility but unused
        _api_secret: String,
        _api_passphrase: String,
    ) -> Result<Self> {
        let wallet: LocalWallet = private_key.parse()?;
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let chain_id = provider.get_chainid().await?.as_u64();
        let wallet = wallet.with_chain_id(chain_id);

        let signer = Arc::new(SignerMiddleware::new(provider, wallet));

        // Check for read-only mode from env
        let read_only = std::env::var("READ_ONLY")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        if read_only {
            warn!("⚠️  READ-ONLY MODE ENABLED - No real orders will be submitted");
        }

        // Get Python executor URL from environment
        let python_executor_url = std::env::var("PYTHON_EXECUTOR_URL")
            .unwrap_or_else(|_| "http://localhost:8765".to_string());

        info!("✅ ClobClient initialized");
        info!("   Python executor: {}", python_executor_url);

        Ok(Self {
            http: Client::new(),
            provider: signer,
            proxy_wallet: Address::from_str(proxy_wallet)?,
            read_only,
            python_executor_url,
        })
    }

    // ==================================================
    // TRADING READINESS CHECK
    // ==================================================

    pub async fn ensure_trading_ready(&self, required_usdc: u128) -> Result<()> {
        self.ensure_balance(required_usdc).await?;

        if self.proxy_is_contract().await? {
            self.ensure_safe_checks().await?;
        } else {
            self.ensure_usdc_allowance().await?;
            self.ensure_erc1155_approval().await?;
        }

        Ok(())
    }

    async fn proxy_is_contract(&self) -> Result<bool> {
        let code = self
            .provider
            .provider()
            .get_code(self.proxy_wallet, None)
            .await?;
        Ok(!code.0.is_empty())
    }

    async fn ensure_balance(&self, required: u128) -> Result<()> {
        let bal = self.usdc().balance_of(self.proxy_wallet).call().await?;
        if bal < U256::from(required) {
            return Err(anyhow!(
                "❌ Insufficient USDC balance. Need: {}, Have: {}",
                required as f64 / 1_000_000.0,
                bal.as_u128() as f64 / 1_000_000.0
            ));
        }
        info!(
            "✅ USDC balance OK: ${:.2}",
            bal.as_u128() as f64 / 1_000_000.0
        );
        Ok(())
    }

    async fn ensure_safe_checks(&self) -> Result<()> {
        let allowance = self
            .usdc()
            .allowance(self.proxy_wallet, self.exchange())
            .call()
            .await?;

        if allowance < U256::from(MIN_ALLOWANCE) {
            return Err(anyhow!(
                "❌ USDC allowance missing on Gnosis Safe. Please approve in Polymarket UI."
            ));
        }

        let approved = self
            .ctf()
            .is_approved_for_all(self.proxy_wallet, self.exchange())
            .call()
            .await?;

        if !approved {
            return Err(anyhow!(
                "❌ ERC-1155 approval missing on Gnosis Safe. Please approve in Polymarket UI."
            ));
        }

        info!("✅ Gnosis Safe approvals OK");
        Ok(())
    }

    async fn ensure_usdc_allowance(&self) -> Result<()> {
        let allowance = self
            .usdc()
            .allowance(self.proxy_wallet, self.exchange())
            .call()
            .await?;

        if allowance >= U256::from(MIN_ALLOWANCE) {
            info!("✅ USDC allowance OK");
            return Ok(());
        }

        warn!("⚠️  Approving USDC spending to Polymarket exchange...");
        let tx = self
            .usdc()
            .approve(self.exchange(), U256::MAX)
            .send()
            .await?
            .await?;

        info!("✅ USDC approved. Tx: {:?}", tx);
        Ok(())
    }

    async fn ensure_erc1155_approval(&self) -> Result<()> {
        let approved = self
            .ctf()
            .is_approved_for_all(self.proxy_wallet, self.exchange())
            .call()
            .await?;

        if approved {
            info!("✅ ERC-1155 approval OK");
            return Ok(());
        }

        warn!("⚠️  Approving ERC-1155 (CTF) to Polymarket exchange...");
        let tx = self
            .ctf()
            .set_approval_for_all(self.exchange(), true)
            .send()
            .await?
            .await?;

        info!("✅ ERC-1155 approved. Tx: {:?}", tx);
        Ok(())
    }

    // ==================================================
    // ORDER SUBMISSION - VIA PYTHON EXECUTOR
    // ==================================================

    pub async fn submit_order(
        &self,
        order: crate::wallet::signer::ClobOrder,
        _sig: Signature,  // Not needed - Python will sign
        _proxy: &str,
    ) -> Result<()> {
        if self.read_only {
            info!("📝 [READ-ONLY] Would submit order:");
            info!("   Token: 0x{}", hex::encode(order.token_id.as_bytes()));
            info!("   Side: {}", if order.side == 0 { "BUY" } else { "SELL" });
            info!(
                "   Maker Amount: {:.6}",
                order.maker_amount.as_u128() as f64 / 1_000_000.0
            );
            info!("   Taker Amount: {:.6}", order.taker_amount.as_u128() as f64 / 1_000_000.0);
            return Ok(());
        }

        // Convert order to format Python executor expects
        #[derive(Serialize, Debug)]
        struct PythonOrderRequest {
            token_id: String,
            side: String,
            price: String,
            size: String,
            order_type: String,
        }

        // Calculate price and size from maker/taker amounts
        let (price, size) = if order.side == 0 {
            // BUY: we're the maker (providing USDC), they're the taker (providing tokens)
            // price = maker_amount / taker_amount
            // size = taker_amount (in token units)
            let price = (order.maker_amount.as_u128() as f64 / 1_000_000.0) 
                       / (order.taker_amount.as_u128() as f64 / 1_000_000.0);
            let size = order.taker_amount.as_u128() as f64 / 1_000_000.0;
            (price, size)
        } else {
            // SELL: we're the maker (providing tokens), they're the taker (providing USDC)
            // price = taker_amount / maker_amount
            // size = maker_amount (in token units)
            let price = (order.taker_amount.as_u128() as f64 / 1_000_000.0)
                       / (order.maker_amount.as_u128() as f64 / 1_000_000.0);
            let size = order.maker_amount.as_u128() as f64 / 1_000_000.0;
            (price, size)
        };

        let python_order = PythonOrderRequest {
            token_id: format!("{:#x}", order.token_id),
            side: if order.side == 0 { "BUY" } else { "SELL" }.to_string(),
            price: format!("{:.6}", price),
            size: format!("{:.6}", size),
            order_type: "FOK".to_string(),  // Fill-or-Kill
        };

        info!("📤 Sending order to Python executor...");
        info!("   Token: {}", &python_order.token_id[..16]);
        info!("   {} price={} size={}", python_order.side, python_order.price, python_order.size);

        let url = format!("{}/order", self.python_executor_url);
        
        let resp = self
            .http
            .post(&url)
            .json(&python_order)
            .timeout(std::time::Duration::from_secs(10))
            .send()
            .await?;

        let status = resp.status();
        
        if !status.is_success() {
            let error_body = resp.text().await?;
            warn!("❌ Python executor rejected order");
            warn!("   Status: {}", status);
            warn!("   Error: {}", error_body);
            return Err(anyhow!("Python executor error: {} - {}", status, error_body));
        }

        // Parse response
        #[derive(Deserialize)]
        struct PythonOrderResponse {
            success: bool,
            order_id: Option<String>,
            error: Option<String>,
        }

        let response: PythonOrderResponse = resp.json().await?;
        
        if response.success {
            if let Some(order_id) = response.order_id {
                info!("✅ Order placed! ID: {}", order_id);
            } else {
                info!("✅ Order placed successfully!");
            }
        } else {
            let error_msg = response.error.unwrap_or_else(|| "Unknown error".to_string());
            return Err(anyhow!("Order failed: {}", error_msg));
        }

        Ok(())
    }

    // ==================================================
    // STUBS FOR FUTURE
    // ==================================================

    pub async fn get_orderbook(&self, _token_id: &str) -> Result<()> {
        Err(anyhow!("Use execution::orderbook::fetch_orderbook instead"))
    }

    pub fn best_price(&self, _book: &(), _side: u8) -> Result<()> {
        Err(anyhow!("Use execution::orderbook methods instead"))
    }

    // ==================================================
    // CONTRACT HELPERS
    // ==================================================

    fn exchange(&self) -> Address {
        Address::from_str(POLYMARKET_EXCHANGE).unwrap()
    }

    fn usdc(&self) -> USDCContract<SignerMiddleware<Provider<Http>, LocalWallet>> {
        USDCContract::new(
            Address::from_str(USDC_ADDRESS).unwrap(),
            self.provider.clone(),
        )
    }

    fn ctf(&self) -> CTFContract<SignerMiddleware<Provider<Http>, LocalWallet>> {
        CTFContract::new(
            Address::from_str(CTF_CONTRACT).unwrap(),
            self.provider.clone(),
        )
    }
}

// ==================================================
// ABI GENERATION
// ==================================================

abigen!(
    USDCContract,
    r#"[
        function balanceOf(address) view returns (uint256)
        function allowance(address,address) view returns (uint256)
        function approve(address,uint256) returns (bool)
    ]"#
);

abigen!(
    CTFContract,
    r#"[
        function isApprovedForAll(address,address) view returns (bool)
        function setApprovalForAll(address,bool)
    ]"#
);
