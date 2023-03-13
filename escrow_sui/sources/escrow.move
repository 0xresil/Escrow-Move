module escrow::escrow {
  use sui::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};

  /// An object held in escrow
  struct EscrowedObj<T: key + store, phantom ExchangeForT: key + store> has key, store {
    id: UID,
    /// owner of the escrowed object
    creator: address,
    /// intended recipient of the escrowed object
    recipient: address,
    /// ID of the object `creator` wants in exchange
    exchange_for: ID,
    /// the escrowed object
    escrowed: Option<T>,
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
  public fun initialize<T: key + store, ExchangeForT: key + store>(
    commission_wallet: address,
    minimum_escrow_amount: u64,
    commission_rate: u64,
    owner: address,
    buyer: address,
    ctx: &mut TxContext
  ) {
      let creator = tx_context::sender(ctx);
      let id = object::new(ctx);
      let escrowed = option::some(escrowed_item);
      transfer::share_object(
          EscrowedObj<T,ExchangeForT> {
              id, creator, recipient, exchange_for, escrowed
          }
      );
  }
}