# @version ^0.3.9

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

event OrderAdded:
    maker: indexed(address)
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: indexed(uint256)

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
    self.owner = msg.sender

@external
def add_trusted_book(
    book: Book
):
    assert msg.sender == self.owner
    self.trusted_books[book] = True

@external
def add_order(
    asset: ERC20,
    amount: uint256,
    desired: ERC20,
    desired_amount: uint256,
):
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
    assert self.orders[nonce].maker == msg.sender, "Cannot cancel someone else's order"
    self.orders[nonce].active = False
    log OrderCancelled(msg.sender, nonce)

@external
def fill_order(
    nonce: uint256
):
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
    print("fill_order_on_book", hardhat_compat=True)
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
    print("on_order_filled", hardhat_compat=True)
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
    assert self.trusted_books[Book(msg.sender)], "Book is not trusted"
    order: Order = Book(msg.sender).orders(nonce)
    # Transfer desired token back to taker
    assert order.desired.transfer(taker, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    log RemoteOrderFillCanceled(Book(msg.sender), nonce)



# _safeTransfer will call transferFrom on the ERC20 contract
# via raw_call, with revert_on_failure=False such that we can both
# catch a revert as well as check the return value in case of no revert
#
# this function will return bool if the transfer was successful, false otherwise
@internal
def _safeTransfer(token: ERC20, _from: address, _to: address, amount: uint256) -> bool:
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

# external wrapper around _safeTransfer
@external
def safeTransfer(token: ERC20, _from: address, _to: address, amount: uint256) -> bool:
    return self._safeTransfer(token, _from, _to, amount)
