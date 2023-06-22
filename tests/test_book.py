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
    maker: "address" # type: ignore
    asset: "address" # type: ignore
    amount: "uint256" # type: ignore
    desired: "address" # type: ignore
    desired_amount: "uint256" # type: ignore
    nonce: "uint256" # type: ignore
    active: "bool" # type: ignore

def test_sigs(maker, tokens, book, taker):
    tokenA, tokenB = tokens[:2]
    order_to_sign = Order(maker.address, tokenA.address, 10, tokenB.address, 20, 0, True) # type: ignore
    message = order_to_sign.signable_message
    signature = maker.sign_message(message)
    order_struct = (maker.address, tokenA.address, 10, tokenB.address, 20, 0, True)
    hashed_book = book.hash_order(order_struct)
    encoded = encode_defunct(primitive=hashed_book)
    sig2 = maker.sign_message(encoded)
    print(hashed_book)
    print(message)
    hashed_message = Web3.keccak(b"\x19\x01" + message.header + message.body)
    encoded_message = encode_defunct(primitive=hashed_message)
    sig3 = maker.sign_message(encoded_message)
    assert sig2 == sig3
    print(hashed_message)
    print(signature, sig2, sig3)
    assert recover_signer(message, signature) == maker.address
    assert recover_signer(encoded, sig2) == maker.address

    assert book.check_order_signature(order_struct, signature.encode_vrs(), maker)
