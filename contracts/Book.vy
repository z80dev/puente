# @version ^0.3.9
"""
@title Order Book
@custom:contract-name Book
@license MIT
@author z80
"""

from vyper.interfaces import ERC20

struct Order:
    maker: address
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: uint256
    active: bool

interface Book:
    def fill_order(nonce: uint256): nonpayable
    def on_order_filled(nonce: uint256, taker: address) -> bool: nonpayable
    def on_remote_fill_cancel(nonce: uint256, taker: address): nonpayable
    def on_remote_fill_confirm(nonce: uint256, taker: address): nonpayable
    def orders(nonce: uint256) -> Order: view

implements: Book

_TYPE_HASH: constant(bytes32) = keccak256("EIP712Domain(string name)")

event OrderAdded:
    maker: indexed(address)
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: indexed(uint256)

@view
@internal
def _hash_order(order: Order) -> bytes32:
    domain_separator: bytes32 = keccak256(
        _abi_encode(
            _TYPE_HASH,
            keccak256("Order"))
        )

    ORDER_TYPE_HASH: bytes32 = keccak256(
        "Order(address maker,address asset,uint256 amount,address desired,uint256 desired_amount,uint256 nonce,bool active)"
        )

    struct_hash: bytes32 = keccak256(
        _abi_encode(
            ORDER_TYPE_HASH,
            order.maker,
            order.asset.address,
            order.amount,
            order.desired.address,
            order.desired_amount,
            order.nonce,
            order.active
        )
        )

    return keccak256(
        concat(
            b"\x19\x01",
            domain_separator,
            struct_hash))

@view
@external
def hash_order(order: Order) -> bytes32:
    return self._hash_order(order)

@view
@external
def check_order_signature(order: Order, signature: Bytes[65], signer: address) -> bool:
    # slice signature into v, r, s
    v: uint256 = convert(slice(signature, 0, 1), uint256)
    r: uint256 = convert(slice(signature, 1, 32), uint256)
    s: uint256 = convert(slice(signature, 33, 32), uint256)
    return ecrecover(self._hash_order(order), v, r, s) == signer

event OrderCancelled:
    maker: indexed(address)
    nonce: indexed(uint256)

event OrderFilled:
    maker: indexed(address)
    taker: indexed(address)
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: indexed(uint256)

event RemoteOrderFillCandidate:
    book: indexed(Book)
    nonce: indexed(uint256)

event RemoteOrderFillConfirmed:
    book: indexed(Book)
    nonce: indexed(uint256)

event RemoteOrderFillCanceled:
    book: indexed(Book)
    nonce: indexed(uint256)

current_nonce: public(uint256)

orders: public(HashMap[uint256, Order])

owner: address

trusted_books: public(HashMap[Book, bool])

@external
def __init__():
    """
    @dev Initializes the contract by setting the sender
         as the contract owner.
    @notice Only executed once when the contract is deployed.
    """
    self.owner = msg.sender

@external
def add_trusted_book(
    book: Book
):
    """
    @dev Adds a new Book instance to the list of trusted books.
    @notice Only the owner of this contract can add a book.
    @param book The instance of the Book contract.
    """
    assert msg.sender == self.owner
    self.trusted_books[book] = True

@external
def add_order(
    asset: ERC20,
    amount: uint256,
    desired: ERC20,
    desired_amount: uint256,
):
    """
    @dev Adds a new order to the list of orders.
    @param asset The token to be exchanged.
    @param amount The amount of the asset token.
    @param desired The token the maker desires in return.
    @param desired_amount The amount of the desired token.
    """
    order: Order = Order({
        maker: msg.sender,
        asset: asset,
        amount: amount,
        desired: desired,
        desired_amount: desired_amount,
        nonce: self.current_nonce,
        active: True
    })
    self.orders[self.current_nonce] = order
    self.current_nonce += 1
    log OrderAdded(msg.sender, asset, amount, desired, desired_amount, self.current_nonce)

@external
def cancel_order(
    nonce: uint256
):
    """
    @dev Cancels an active order.
    @notice Only the maker of the order can cancel it.
    @param nonce The unique identifier of the order.
    """
    assert self.orders[nonce].maker == msg.sender, "Cannot cancel someone else's order"
    self.orders[nonce].active = False
    log OrderCancelled(msg.sender, nonce)

@external
def fill_order(
    nonce: uint256
):
    """
    @dev Fills an active order.
    @notice The maker of the order cannot fill it.
    @param nonce The unique identifier of the order.
    """
    order: Order = self.orders[nonce]
    assert order.active, "Order is not active"
    assert order.maker != msg.sender, "Cannot fill your own order"
    assert order.desired.transferFrom(msg.sender, order.maker, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    assert order.asset.transferFrom(order.maker, msg.sender, order.amount, default_return_value=True), "Failed to transfer asset token"
    self.orders[nonce].active = False
    log OrderFilled(order.maker, msg.sender, order.asset, order.amount, order.desired, order.desired_amount, nonce)

@external
def fill_order_on_book(
    nonce: uint256,
    book: Book
):
    """
    @dev Fills an active order on a different Book.
    @notice The maker of the order cannot fill it.
            The book must be in the list of trusted books.
    @param nonce The unique identifier of the order.
    @param book The Book instance on which the order is filled.
    """
    order: Order = book.orders(nonce)
    assert order.maker != msg.sender, "Cannot fill your own order"
    assert self.trusted_books[book], "Book is not trusted"
    # Transfer desired token to this contract until remote fill is confirmed
    assert order.desired.transferFrom(msg.sender, self, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    log RemoteOrderFillCandidate(book, nonce)
    assert book.on_order_filled(nonce, msg.sender)

@external
def on_order_filled(
    nonce: uint256,
    taker: address
) -> bool:
    """
    @dev Handles the event when an order is filled.
    @notice Only trusted Books can call this method.
    @param nonce The unique identifier of the order.
    @param taker The address of the taker who fills the order.
    @return bool Whether the fill was successful or not.
    """
    assert self.trusted_books[Book(msg.sender)], "Book is not trusted"

    order: Order = self.orders[nonce]

    if not order.active:
        Book(msg.sender).on_remote_fill_cancel(nonce, taker)
    else:
        self.orders[nonce].active = False
        if self._safeTransfer(order.asset, order.maker, taker, order.amount):
            Book(msg.sender).on_remote_fill_confirm(nonce, taker)
            log OrderFilled(order.maker, taker, order.asset, order.amount, order.desired, order.desired_amount, nonce)
        else:
            # cancel, return desired token to taker
            # leave order inactive since maker failed to keep up their end
            Book(msg.sender).on_remote_fill_cancel(nonce, taker)

    return True

@external
def on_remote_fill_confirm(
        nonce: uint256,
        taker: address
):
    """
    @dev Confirms the fill of an order on a remote Book.
    @notice Only trusted Books can call this method.
    @param nonce The unique identifier of the order.
    @param taker The address of the taker who filled the order.
    """
    assert self.trusted_books[Book(msg.sender)], "Book is not trusted"
    order: Order = Book(msg.sender).orders(nonce)
    # Transfer desired token to maker
    assert order.desired.transfer(order.maker, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    log RemoteOrderFillConfirmed(Book(msg.sender), nonce)

@external
def on_remote_fill_cancel(
        nonce: uint256,
        taker: address
):
    """
    @dev Cancels the fill of an order on a remote Book.
    @notice Only trusted Books can call this method.
    @param nonce The unique identifier of the order.
    @param taker The address of the taker who tried to fill the order.
    """
    assert self.trusted_books[Book(msg.sender)], "Book is not trusted"
    order: Order = Book(msg.sender).orders(nonce)
    # Transfer desired token back to taker
    assert order.desired.transfer(taker, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    log RemoteOrderFillCanceled(Book(msg.sender), nonce)



@internal
def _safeTransfer(token: ERC20, _from: address, _to: address, amount: uint256) -> bool:
    """
    @dev Safely transfers `amount` tokens from `_from` to `_to` by
         calling `transferFrom` on the ERC20 token contract.
    @notice This method catches reverts and checks the return value
            in case of no revert.
    @param token The ERC20 token to be transferred.
    @param _from The address from which the tokens are transferred.
    @param _to The address to which the tokens are transferred.
    @param amount The amount of tokens to be transferred.
    @return bool Whether the transfer was successful or not.
    """
    success: bool = False
    response: Bytes[32] = b'\x00'
    success, response = raw_call(
        token.address,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(_from, bytes32),
            convert(_to, bytes32),
            convert(amount, bytes32)
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    if success:
        return convert(response, bool)
    else:
        return False
