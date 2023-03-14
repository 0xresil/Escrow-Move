module escrow::escrow {
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Balance};
  use sui::object::{Self, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::sui::SUI;
  use sui::clock::{Self, Clock};

  //
  // Escrow Status
  //
  
  const ESCROW_STATUS_INITED: u64 = 0;
  const ESCROW_STATUS_FUNDED: u64 = 1;
  const ESCROW_STATUS_ACCEPTED: u64 = 2;
  const ESCROW_STATUS_RELEASED: u64 = 3;
  const ESCROW_STATUS_REFUNDED: u64 = 4;
  const ESCROW_STATUS_OWNERWITHDRAW: u64 = 5;

  //
  // Errors
  //
  
  const EINVALID_OWNER: u64 = 1;
  const EESCROW_ALREADY_INITED: u64 = 2;
  const EINVALID_PARTIES: u64 = 3;
  const EINVALID_ACTION: u64 = 4;
  const EINVALID_AMOUNT: u64 = 5;
  const EINVALID_STATUS: u64 = 6;
  const EINVALID_TIME: u64 = 7;
  const EINVALID_COMMISSION_RATE: u64 = 8;
  const EINVALID_ADDRESS: u64 = 9;

  struct EscrowInfo has key {
      id: UID,
      // owner address of escrow
      owner: address,
      // Fee amount in aptos
      commission_rate: u64,
      // minimum deposit amount
      minimum_escrow_amount: u64,
      // fee receiver wallet
      commission_wallet: address,
      // buyer address
      buyer: address,
      // seller address
      seller: address,
      // deposit time in unix timestamp
      deposit_time: u64,
      // escrow status
      status: u64,
      // coins in escrow
      escrowed: Balance<SUI>
  }

  // Error codes
  /// An attempt to cancel escrow by a different user than the owner
  const EWrongOwner: u64 = 0;
  /// Exchange by a different user than the `recipient` of the escrowed object
  const EWrongRecipient: u64 = 1;
  /// Exchange with a different item than the `exchange_for` field
  const EWrongExchangeObject: u64 = 2;
  /// The escrow has already been exchanged or cancelled
  const EAlreadyExchangedOrCancelled: u64 = 3;

  /// Create an escrow for exchanging goods with counterparty
  public fun initialize(
    commission_wallet: address,
    minimum_escrow_amount: u64,
    commission_rate: u64,
    owner: address,
    buyer: address,
    ctx: &mut TxContext
  ) {

      // notCommissionWallet(_owner)
      assert!(commission_wallet != owner, EINVALID_ADDRESS);
      // notCommissionWallet(buyer)
      assert!(commission_wallet != buyer, EINVALID_ADDRESS);
      // distinctAddresses(_buyer, owner)
      assert!(owner != buyer, EINVALID_ADDRESS);

      let id = object::new(ctx);
      transfer::share_object(
          EscrowInfo {
              id, 
              owner,
              commission_rate,
              minimum_escrow_amount,
              commission_wallet,
              buyer,
              seller: buyer,
              deposit_time: 0,
              status: 0,
              escrowed: balance::zero<SUI>()
          }
      );
  }

  entry fun deposit(
    sui: Coin<SUI>,
    clock: &Clock,
    escrow: &mut EscrowInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // buyerOnly(_buyer)
    assert!(sender == escrow.buyer, EINVALID_ADDRESS);
    // minimumAmount
    assert!(coin::value(&sui) > escrow.minimum_escrow_amount, EINVALID_AMOUNT);
    
    escrow.deposit_time = clock::timestamp_ms(clock);
    escrow.status = ESCROW_STATUS_FUNDED;
    
    let sui_balance = coin::into_balance(sui);
    balance::join(&mut escrow.escrowed, sui_balance);
  }

  entry fun accept_deal(
    escrow: &mut EscrowInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // stateFunded
    assert!(escrow.status == ESCROW_STATUS_FUNDED, EINVALID_STATUS);
    // distinctAddresses(_buyer, owner)
    assert!(sender != escrow.buyer, EINVALID_ADDRESS);

    escrow.seller = sender;
    escrow.status = ESCROW_STATUS_ACCEPTED;
  }

  entry fun release_fund(
    escrow: &mut EscrowInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // buyerOnly(_buyer)
    assert!(sender == escrow.buyer || sender == escrow.seller, EINVALID_ADDRESS);
    // stateAccepted
    assert!(escrow.status == ESCROW_STATUS_ACCEPTED, EINVALID_STATUS);

    escrow.status = ESCROW_STATUS_RELEASED;
    let (
      amt_after_commission, 
      commission_amount
    ) = calculate_amount_to_transfer(escrow);

    let sui_after_commission: Coin<SUI> = coin::take(&mut escrow.escrowed, amt_after_commission, ctx);
    if (sender == escrow.seller) {
      transfer::transfer(sui_after_commission, escrow.buyer);
    } else {
      transfer::transfer(sui_after_commission, escrow.seller);
    };

    let sui_commission: Coin<SUI> = coin::take(&mut escrow.escrowed, commission_amount, ctx);
    transfer::transfer(sui_commission, escrow.commission_wallet);
  }

  entry fun withdraw_fund(
    escrow: &mut EscrowInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // buyerOnly
    assert!(sender == escrow.buyer, EINVALID_ADDRESS);
    // stateFunded
    assert!(escrow.status == ESCROW_STATUS_FUNDED, EINVALID_STATUS);

    escrow.status = ESCROW_STATUS_REFUNDED;

    let (
      amt_after_commission, 
      commission_amount
    ) = calculate_amount_to_transfer(escrow);

    let sui_after_commission: Coin<SUI> = coin::take(&mut escrow.escrowed, amt_after_commission, ctx);
    transfer::transfer(sui_after_commission, escrow.buyer);

    let sui_commission: Coin<SUI> = coin::take(&mut escrow.escrowed, commission_amount, ctx);
    transfer::transfer(sui_commission, escrow.commission_wallet);
  }

  entry fun post_six_months(
    clock: &Clock,
    escrow: &mut EscrowInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // onlyOwner
    assert!(sender == escrow.owner, EINVALID_ADDRESS);
    // stateAccepted
    assert!(escrow.status == ESCROW_STATUS_ACCEPTED, EINVALID_STATUS);
    // minimumTimePeriod
    let six_month = 60 * 60 * 24 * 180;
    assert!(clock::timestamp_ms(clock) > escrow.deposit_time + six_month, EINVALID_TIME);

    escrow.status = ESCROW_STATUS_OWNERWITHDRAW;

    let remained_amt = balance::value(&escrow.escrowed);
    let sui_remained: Coin<SUI> = coin::take(&mut escrow.escrowed, remained_amt, ctx);
    transfer::transfer(sui_remained, sender);
  }

  public fun calculate_amount_to_transfer(escrow_info: &mut EscrowInfo): (u64, u64) {
      let deal_amount = balance::value(&escrow_info.escrowed);
      let amt_after_commission = deal_amount -
          ((deal_amount * escrow_info.commission_rate) / 100);
      let commission_amount = deal_amount - amt_after_commission;
      (amt_after_commission, commission_amount)
  }

  
}