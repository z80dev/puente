import ape

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
