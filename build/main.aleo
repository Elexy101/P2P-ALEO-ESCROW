import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import credits.aleo;
program p2p_private_escrow.aleo;

record SellerReceipt:
    owner as address.private;
    trade_id as field.private;
    secret_hash as field.private;
    amount as u128.private;

struct Trade:
    trade_id as field;
    seller_hash as field;
    buyer_hash as field;
    amount as u128;
    secret_hash as field;
    status as u8;
    created_at as u32;
    expires_at as u32;

mapping trades:
    key as field.public;
    value as Trade.public;

mapping used_secrets:
    key as field.public;
    value as boolean.public;

mapping total_trades:
    key as u32.public;
    value as u32.public;

function create_escrow:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as u128.public;
    input r3 as field.public;
    input r4 as test_usdcx_stablecoin.aleo/Token.record;
    input r5 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    cast self.caller into r6 as field;
    hash.bhp256 r6 into r7 as field;
    cast r1 into r8 as field;
    hash.bhp256 r8 into r9 as field;
    call test_usdcx_stablecoin.aleo/transfer_private p2p_private_escrow.aleo r2 r4 r5 into r10 r11 r12 r13;
    cast self.caller r0 r3 r2 into r14 as SellerReceipt.record;
    async create_escrow r13 r2 r1 self.caller r3 r0 r7 r9 into r15;
    output r14 as SellerReceipt.record;
    output r15 as p2p_private_escrow.aleo/create_escrow.future;

finalize create_escrow:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as u128.public;
    input r2 as address.public;
    input r3 as address.public;
    input r4 as field.public;
    input r5 as field.public;
    input r6 as field.public;
    input r7 as field.public;
    await r0;
    gte r1 1000000u128 into r8;
    assert.eq r8 true;
    is.neq r2 r3 into r9;
    assert.eq r9 true;
    is.neq r4 0field into r10;
    assert.eq r10 true;
    contains trades[r5] into r11;
    not r11 into r12;
    assert.eq r12 true;
    add block.height 5000u32 into r13;
    cast r5 r6 r7 r1 r4 0u8 block.height r13 into r14 as Trade;
    set r14 into trades[r5];
    get.or_use total_trades[0u32] 0u32 into r15;
    add r15 1u32 into r16;
    set r16 into total_trades[0u32];

function release_funds:
    input r0 as field.public;
    input r1 as address.private;
    input r2 as field.private;
    input r3 as SellerReceipt.record;
    cast self.caller into r4 as field;
    hash.bhp256 r4 into r5 as field;
    is.eq r3.owner self.caller into r6;
    assert.eq r6 true;
    is.eq r3.trade_id r0 into r7;
    assert.eq r7 true;
    call test_usdcx_stablecoin.aleo/transfer_public r1 r3.amount into r8;
    async release_funds r0 r5 r3.amount r2 r3.secret_hash r8 into r9;
    output r9 as p2p_private_escrow.aleo/release_funds.future;

finalize release_funds:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u128.public;
    input r3 as field.public;
    input r4 as field.public;
    input r5 as test_usdcx_stablecoin.aleo/transfer_public.future;
    get trades[r0] into r6;
    is.eq r6.seller_hash r1 into r7;
    assert.eq r7 true;
    is.eq r6.status 0u8 into r8;
    assert.eq r8 true;
    is.eq r6.amount r2 into r9;
    assert.eq r9 true;
    lte block.height r6.expires_at into r10;
    assert.eq r10 true;
    hash.bhp256 r3 into r11 as field;
    is.eq r11 r6.secret_hash into r12;
    assert.eq r12 true;
    is.eq r11 r4 into r13;
    assert.eq r13 true;
    get.or_use used_secrets[r11] false into r14;
    not r14 into r15;
    assert.eq r15 true;
    set true into used_secrets[r11];
    await r5;
    cast r6.trade_id r6.seller_hash r6.buyer_hash r6.amount r6.secret_hash 1u8 r6.created_at r6.expires_at into r16 as Trade;
    set r16 into trades[r0];

function refund_seller:
    input r0 as field.public;
    input r1 as SellerReceipt.record;
    cast self.caller into r2 as field;
    hash.bhp256 r2 into r3 as field;
    is.eq r1.owner self.caller into r4;
    assert.eq r4 true;
    is.eq r1.trade_id r0 into r5;
    assert.eq r5 true;
    call test_usdcx_stablecoin.aleo/transfer_public self.caller r1.amount into r6;
    async refund_seller r0 r3 r1.amount r6 into r7;
    output r7 as p2p_private_escrow.aleo/refund_seller.future;

finalize refund_seller:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u128.public;
    input r3 as test_usdcx_stablecoin.aleo/transfer_public.future;
    get trades[r0] into r4;
    is.eq r4.seller_hash r1 into r5;
    assert.eq r5 true;
    is.eq r4.status 0u8 into r6;
    assert.eq r6 true;
    is.eq r4.amount r2 into r7;
    assert.eq r7 true;
    gt block.height r4.expires_at into r8;
    assert.eq r8 true;
    await r3;
    cast r4.trade_id r4.seller_hash r4.buyer_hash r4.amount r4.secret_hash 2u8 r4.created_at r4.expires_at into r9 as Trade;
    set r9 into trades[r0];

function cancel_trade:
    input r0 as field.public;
    input r1 as SellerReceipt.record;
    cast self.caller into r2 as field;
    hash.bhp256 r2 into r3 as field;
    is.eq r1.owner self.caller into r4;
    assert.eq r4 true;
    is.eq r1.trade_id r0 into r5;
    assert.eq r5 true;
    call test_usdcx_stablecoin.aleo/transfer_public self.caller r1.amount into r6;
    async cancel_trade r0 r3 r1.amount r6 into r7;
    output r7 as p2p_private_escrow.aleo/cancel_trade.future;

finalize cancel_trade:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u128.public;
    input r3 as test_usdcx_stablecoin.aleo/transfer_public.future;
    get trades[r0] into r4;
    is.eq r4.seller_hash r1 into r5;
    assert.eq r5 true;
    is.eq r4.status 0u8 into r6;
    assert.eq r6 true;
    is.eq r4.amount r2 into r7;
    assert.eq r7 true;
    await r3;
    cast r4.trade_id r4.seller_hash r4.buyer_hash r4.amount r4.secret_hash 2u8 r4.created_at r4.expires_at into r8 as Trade;
    set r8 into trades[r0];

constructor:
    assert.eq edition 0u16;
