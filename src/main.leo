// p2p_private_escrow.leo
// PRIVATE P2P ESCROW - Anonymous fiat-to-crypto exchange

import credits.aleo;
import test_usdcx_stablecoin.aleo;

program p2p_private_escrow.aleo {
    
    @noupgrade
    constructor() {}


    // ==============================================
    // DATA STRUCTURES
    // ==============================================

    struct Trade {
        trade_id: field,
        seller_hash: field,
        buyer_hash: field,
        amount: u128,
        secret_hash: field,
        status: u8,
        created_at: u32,
        expires_at: u32,
    }

    record SellerReceipt {
        owner: address,
        trade_id: field,
        secret_hash: field,
        amount: u128,
    }

    // ==============================================
    // STORAGE MAPPINGS
    // ==============================================

    mapping trades: field => Trade;
    mapping used_secrets: field => bool;
    mapping total_trades: u32 => u32;

    // ==============================================
    // CONSTANTS
    // ==============================================

    const STATUS_PENDING: u8 = 0u8;
    const STATUS_RELEASED: u8 = 1u8;
    const STATUS_REFUNDED: u8 = 2u8;
    const ESCROW_TIMEOUT_BLOCKS: u32 = 5000u32;
    const MIN_TRADE_AMOUNT: u128 = 1000000u128;

    // ==============================================
    // CREATE ESCROW
    // ==============================================

    fn create_escrow(
        public trade_id: field,
        public buyer: address,
        public amount: u128,
        public secret_hash: field,
        private seller_token: test_usdcx_stablecoin.aleo::Token,
        private proofs: [test_usdcx_stablecoin.aleo::MerkleProof; 2]
    ) -> (SellerReceipt, Final) {
        
        let seller: address = self.caller;
        let seller_hash: field = BHP256::hash_to_field(seller as field);
        let buyer_hash: field = BHP256::hash_to_field(buyer as field);
        
        // Transfer USDCx to contract
        let (compliance, updated_token, escrowed_token, transfer_future): (
            test_usdcx_stablecoin.aleo::ComplianceRecord, 
            test_usdcx_stablecoin.aleo::Token, 
            test_usdcx_stablecoin.aleo::Token, 
            Final
        ) = test_usdcx_stablecoin.aleo::transfer_private(
            self.address, 
            amount, 
            seller_token, 
            proofs
        );
        
        // Create receipt for seller
        let seller_receipt: SellerReceipt = SellerReceipt {
            owner: seller,
            trade_id: trade_id,
            secret_hash: secret_hash,
            amount: amount,
        };
        
        return (
            seller_receipt,
            final {
                transfer_future.run();
                
                let current_height: u32 = block.height;
                
                assert(amount >= MIN_TRADE_AMOUNT);
                assert(buyer != seller);
                assert(secret_hash != 0field);
                
                let trade_exists: bool = Mapping::contains(trades, trade_id);
                assert(!trade_exists);
                
                let expires_at: u32 = current_height + ESCROW_TIMEOUT_BLOCKS;

                let trade: Trade = Trade {
                    trade_id: trade_id,
                    seller_hash: seller_hash,
                    buyer_hash: buyer_hash,
                    amount: amount,
                    secret_hash: secret_hash,
                    status: STATUS_PENDING,
                    created_at: current_height,
                    expires_at: expires_at,
                };

                Mapping::set(trades, trade_id, trade);
                
                let trade_count: u32 = Mapping::get_or_use(total_trades, 0u32, 0u32);
                Mapping::set(total_trades, 0u32, trade_count + 1u32);
            }
        );
    }

    // ==============================================
    // RELEASE FUNDS (After off-chain fiat payment)
    // ==============================================

    fn release_funds(
        public trade_id: field,
        private buyer: address,
        private secret: field,
        private seller_receipt: SellerReceipt
    ) -> Final {
        
        let caller: address = self.caller;
        let caller_hash: field = BHP256::hash_to_field(caller as field);
        
        // Extract values from receipt before final block
        let receipt_trade_id: field = seller_receipt.trade_id;
        let receipt_secret_hash: field = seller_receipt.secret_hash;
        let receipt_amount: u128 = seller_receipt.amount;
        
        // Verify receipt ownership
        assert(seller_receipt.owner == caller);
        assert(receipt_trade_id == trade_id);
    
        // Transfer USDCx to buyer
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(buyer, seller_receipt.amount);
            
        return final {
            let current_height: u32 = block.height;
            let trade: Trade = Mapping::get(trades, trade_id);
            
            // Verify seller
            assert(trade.seller_hash == caller_hash);
            assert(trade.status == STATUS_PENDING);
            assert(trade.amount == receipt_amount);
            assert(current_height <= trade.expires_at);
            
            // Verify secret
            let computed_hash: field = BHP256::hash_to_field(secret);
            assert(computed_hash == trade.secret_hash);
            assert(computed_hash == receipt_secret_hash);
            
            // Prevent replay attacks
            let secret_used: bool = Mapping::get_or_use(used_secrets, computed_hash, false);
            assert(!secret_used);
            
            // Mark secret as used
            Mapping::set(used_secrets, computed_hash, true);
            
            transfer_future.run();
            
            // Update trade status
            let updated_trade: Trade = Trade {
                trade_id: trade.trade_id,
                seller_hash: trade.seller_hash,
                buyer_hash: trade.buyer_hash,
                amount: trade.amount,
                secret_hash: trade.secret_hash,
                status: STATUS_RELEASED,
                created_at: trade.created_at,
                expires_at: trade.expires_at,
            };
            Mapping::set(trades, trade_id, updated_trade);
        };
    }

    // ==============================================
    // REFUND SELLER (If buyer never pays)
    // ==============================================

    fn refund_seller(
        public trade_id: field,
        private seller_receipt: SellerReceipt
    ) -> Final {
        
        let caller: address = self.caller;
        let caller_hash: field = BHP256::hash_to_field(caller as field);
        
        // Extract values from receipt
        let receipt_trade_id: field = seller_receipt.trade_id;
        let receipt_amount: u128 = seller_receipt.amount;
        
        // Verify receipt ownership
        assert(seller_receipt.owner == caller);
        assert(receipt_trade_id == trade_id);
    
        // Refund USDCx back to seller
        let refund_transfer: Final = test_usdcx_stablecoin.aleo::transfer_public(caller, seller_receipt.amount);
            
        return final {
            let current_height: u32 = block.height;
            let trade: Trade = Mapping::get(trades, trade_id);
            
            // Verify seller and status
            assert(trade.seller_hash == caller_hash);
            assert(trade.status == STATUS_PENDING);
            assert(trade.amount == receipt_amount);
            assert(current_height > trade.expires_at);
            
            refund_transfer.run();
            
            // Update trade status
            let updated_trade: Trade = Trade {
                trade_id: trade.trade_id,
                seller_hash: trade.seller_hash,
                buyer_hash: trade.buyer_hash,
                amount: trade.amount,
                secret_hash: trade.secret_hash,
                status: STATUS_REFUNDED,
                created_at: trade.created_at,
                expires_at: trade.expires_at,
            };
            Mapping::set(trades, trade_id, updated_trade);
        };
    }

    // ==============================================
    // CANCEL TRADE (Seller before expiry)
    // ==============================================

    fn cancel_trade(
        public trade_id: field,
        private seller_receipt: SellerReceipt
    ) -> Final {
        
        let caller: address = self.caller;
        let caller_hash: field = BHP256::hash_to_field(caller as field);
        
        // Extract values from receipt
        let receipt_trade_id: field = seller_receipt.trade_id;
        let receipt_amount: u128 = seller_receipt.amount;
        
        // Verify receipt ownership
        assert(seller_receipt.owner == caller);
        assert(receipt_trade_id == trade_id);
        
        // Immediate refund
        let refund_transfer: Final = test_usdcx_stablecoin.aleo::transfer_public(caller, seller_receipt.amount);
           
        return final {
            let trade: Trade = Mapping::get(trades, trade_id);
            
            // Verify seller and status
            assert(trade.seller_hash == caller_hash);
            assert(trade.status == STATUS_PENDING);
            assert(trade.amount == receipt_amount);
            
             refund_transfer.run();
            
            // Update trade status
            let updated_trade: Trade = Trade {
                trade_id: trade.trade_id,
                seller_hash: trade.seller_hash,
                buyer_hash: trade.buyer_hash,
                amount: trade.amount,
                secret_hash: trade.secret_hash,
                status: STATUS_REFUNDED,
                created_at: trade.created_at,
                expires_at: trade.expires_at,
            };
            Mapping::set(trades, trade_id, updated_trade);
        };
    }
    
    // ==============================================
    // VIEW FUNCTIONS
    // ==============================================
    
}