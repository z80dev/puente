import ape
from web3 import Web3
from eth_account.messages import encode_defunct
from eip712.messages import EIP712Message
from ape.types.signatures import recover_signer

def test_book_add_order(maker, tokens, book):
    # add order
    tx = book.add_order(tokens[0], 10, tokens[1], 20, sender=maker)
    assert tx.events == [book.OrderAdded(maker, tokens[0], 10, tokens[1], 20, 0)]
    assert book.orders(0) == (maker, tokens[0], 10, tokens[1], 20, 0, True)
    assert book.current_nonce() == 1

def test_book_fill_order(maker, taker, tokens, book):

    book.add_order(tokens[0], 10, tokens[1], 20, sender=maker)

    # fill order
    tokens[0].approve(book.address, 10, sender=maker)
    tokens[1].approve(book.address, 20, sender=taker)
    tx = book.fill_order(0, sender=taker)

    assert tokens[0].Transfer(maker, taker, 10) in tx.events
    assert tokens[1].Transfer(taker, maker, 20) in tx.events
    assert book.OrderFilled(maker, taker, tokens[0], 10, tokens[1], 20, 0) in tx.events

def test_book_cannot_fill_cancelled_order(maker, taker, tokens, book):

    book.add_order(tokens[0], 10, tokens[1], 20, sender=maker)
    book.cancel_order(0, sender=maker)

    # fill order
    tokens[0].approve(book.address, 10, sender=maker)
    tokens[1].approve(book.address, 20, sender=taker)

    with ape.reverts("Order is not active"):
        book.fill_order(0, sender=taker)

def test_cannot_use_untrusted_book(maker, taker, tokens, books, book):
    tokenA, tokenB = tokens[:2]
    bookA = books[0]

    bookA.add_order(tokenA, 10, tokenB, 20, sender=maker)

    with ape.reverts("Book is not trusted"):
        book.fill_order_on_book(0, bookA, sender=taker)

def test_books(tokens, books, maker, taker):

    tokenA, tokenB = tokens[:2]
    book_a, book_b = books

    book_a.add_order(tokenA, 10, tokenB, 20, sender=maker)

    maker_start_bal = tokenA.balanceOf(maker)
    taker_start_bal = tokenB.balanceOf(taker)

    tokenA.approve(book_a.address, 10, sender=maker)
    tokenB.approve(book_b.address, 20, sender=taker)

    # fill order
    tx = book_b.fill_order_on_book(0, book_a, sender=taker)

    assert tokenB.Transfer(taker, book_b, 20) in tx.events
    assert tokenA.Transfer(maker, taker, 10) in tx.events
    assert tokenB.Transfer(book_b, maker, 20) in tx.events

    assert book_b.RemoteOrderFillCandidate(book_a.address, 0) in tx.events
    assert book_b.RemoteOrderFillConfirmed(book_a.address, 0) in tx.events

    assert tokenA.balanceOf(maker) == maker_start_bal - 10
    assert tokenB.balanceOf(taker) == taker_start_bal - 20

def test_books_cancel(tokens, books, maker, taker, turtle):

    tokenA, tokenB = tokens[:2]
    book_a, book_b = books

    book_a.add_order(tokenA, 10, tokenB, 20, sender=maker)
    book_a.cancel_order(0, sender=maker)

    tokenB.approve(book_b.address, 20, sender=turtle)
    tx = book_b.fill_order_on_book(0, book_a, sender=turtle)

    assert tokenB.Transfer(turtle, book_b, 20) in tx.events
    assert tokenB.Transfer(book_b, turtle, 20) in tx.events

    assert book_b.RemoteOrderFillCandidate(book_a.address, 0) in tx.events
    assert book_b.RemoteOrderFillCanceled(book_a.address, 0) in tx.events

    tokenB.approve(book_b.address, 20, sender=turtle)

def test_books_cancel_already_filled(tokens, books, maker, taker, turtle):

    tokenA, tokenB = tokens[:2]
    book_a, book_b = books

    book_a.add_order(tokenA, 10, tokenB, 20, sender=maker)

    tokenA.approve(book_a.address, 10, sender=maker)
    tokenB.approve(book_b.address, 20, sender=taker)
    book_b.fill_order_on_book(0, book_a, sender=taker)

    tokenB.approve(book_b.address, 20, sender=turtle)
    tx = book_b.fill_order_on_book(0, book_a, sender=turtle)

    assert tokenB.Transfer(turtle, book_b, 20) in tx.events
    assert tokenB.Transfer(book_b, turtle, 20) in tx.events

    assert book_b.RemoteOrderFillCandidate(book_a.address, 0) in tx.events
    assert book_b.RemoteOrderFillCanceled(book_a.address, 0) in tx.events

def test_books_cancel_maker_canceled_approval(tokens, books, maker, taker, turtle):

    tokenA, tokenB = tokens[:2]
    book_a, book_b = books

    book_a.add_order(tokenA, 10, tokenB, 20, sender=maker)

    tokenB.approve(book_b.address, 20, sender=taker)
    tx = book_b.fill_order_on_book(0, book_a, sender=taker)

    assert book_b.RemoteOrderFillCandidate(book_a.address, 0) in tx.events
    assert book_b.RemoteOrderFillCanceled(book_a.address, 0) in tx.events


class Order(EIP712Message):
    _name_: "string" = "Order" # type: ignore
    _version_: "string" = "1.0" # type: ignore
    # _chainId_: "uint256" = 0 # type: ignore
    # _verifyingContract_: "address" = "0xe65016D97897393a7A104E4c6Eb20bA8D4aCf1E9" # type: ignore
    maker: "address" # type: ignore
    asset: "address" # type: ignore
    amount: "uint256" # type: ignore
    desired: "address" # type: ignore
    desired_amount: "uint256" # type: ignore
    nonce: "uint256" # type: ignore
    active: "bool" # type: ignore

class XOrder(EIP712Message):
    _name_: "string" = "XOrder" # type: ignore
    _version_: "string" = "1.0" # type: ignore
    source_domain: "uint256" # type: ignore
    target_domain: "uint256" # type: ignore
    maker: "address" # type: ignore
    asset: "address" # type: ignore
    amount: "uint256" # type: ignore
    desired: "address" # type: ignore
    desired_amount: "uint256" # type: ignore
    nonce: "uint256" # type: ignore

def test_order_sigs(maker, tokens, book, taker):
    tokenA, tokenB = tokens[:2]
    order_to_sign = Order(maker.address, tokenA.address, 10, tokenB.address, 20, 0, True) # type: ignore
    assert book.domain() == 0
    order_to_sign._chainId_ = 31337
    order_to_sign._verifyingContract_ = book.address
    message = order_to_sign.signable_message
    signature = maker.sign_message(message)
    order_struct = (maker.address, tokenA.address, 10, tokenB.address, 20, 0, True)
    assert recover_signer(message, signature) == maker.address

    assert book.check_order_signature(order_struct, signature.encode_vrs(), maker)

def test_xorder_sigs(maker, tokens, book, taker):
    tokenA, tokenB = tokens[:2]
    order_to_sign = XOrder(0, 1, maker.address, tokenA.address, 10, tokenB.address, 20, 0) # type: ignore
    order_to_sign._chainId_ = 31337
    order_to_sign._verifyingContract_ = book.address
    print(order_to_sign)
    message = order_to_sign.signable_message
    signature = maker.sign_message(message)
    order_struct = (0, 1, maker.address, tokenA.address, 10, tokenB.address, 20, 0)
    assert recover_signer(message, signature) == maker.address

    assert book.check_xorder_signature(order_struct, signature.encode_vrs(), maker)

def test_fill_sig_order(maker, taker, book, tokens):
    tokenA, tokenB = tokens[:2]
    order_to_sign = Order(maker.address, tokenA.address, 10, tokenB.address, 20, 0, True) # type: ignore
    order_to_sign._chainId_ = 31337
    order_to_sign._verifyingContract_ = book.address
    message = order_to_sign.signable_message
    signature = maker.sign_message(message)
    order_struct = (maker.address, tokenA.address, 10, tokenB.address, 20, 0, True)

    # token approvals
    tokenA.approve(book.address, 10, sender=maker)
    tokenB.approve(book.address, 20, sender=taker)

    tx = book.fill_signed_order(order_struct, signature.encode_vrs(), sender=taker)

    # check for token transfer events
    # tokens move directly between maker and taker
    assert tokenA.Transfer(maker, taker, 10) in tx.events
    assert tokenB.Transfer(taker, maker, 20) in tx.events

    # check for order events
    # should be an OrderFilled event
    assert book.OrderFilled(maker.address, taker, tokenA.address, 10, tokenB.address, 20, 0) in tx.events

def test_validate_xorder(maker, taker, books, tokens):
    tokenA, tokenB = tokens[:2]
    book_a, book_b = books
    order_to_sign = XOrder(1, 2, maker.address, tokenA.address, 10, tokenB.address, 20, 0) # type: ignore
    order_to_sign._chainId_ = 31337
    order_to_sign._verifyingContract_ = book_b.address
    message = order_to_sign.signable_message
    signature = maker.sign_message(message)
    order_struct = (1, 2, maker.address, tokenA.address, 10, tokenB.address, 20, 0)

    # Check we can validate a valid xorder
    assert book_b.validate_xorder(order_struct, signature.encode_vrs())

    # Check that we reject an xorder signed by anyone but the maker
    imposter_signature = taker.sign_message(message)
    assert not book_b.validate_xorder(order_struct, imposter_signature.encode_vrs())

    # Check that we reject an xorder with a different target domain
    assert not book_a.validate_xorder(order_struct, signature.encode_vrs())
