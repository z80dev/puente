# @version ^0.3.9
"""
@title Order Book
@custom:contract-name Book
@license MIT
@author z80
"""

from vyper.interfaces import ERC20

################################################################
#                        ORDER STRUCTS                         #
################################################################

# may be used for on-chain orders to be placed by a smart contract
struct Order:
    maker: address
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: uint256
    active: bool

# Struct for XOrders (cross-domain orders)
struct XOrder:
    source_domain: uint256
    target_domain: uint256
    maker: address
    asset: ERC20
    amount: uint256
    desired: ERC20
    desired_amount: uint256
    nonce: uint256

################################################################
#                          INTERFACES                          #
################################################################

interface Book:
    def fill_order(nonce: uint256): nonpayable
    def on_order_filled(nonce: uint256, taker: address) -> bool: nonpayable
    def on_remote_fill_cancel(nonce: uint256, taker: address): nonpayable
    def on_remote_fill_confirm(nonce: uint256, taker: address): nonpayable
    def orders(nonce: uint256) -> Order: view

implements: Book

################################################################
#                            EVENTS                            #
################################################################

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

################################################################
#                       STATE VARIABLES                        #
################################################################

# Mapping for canceled XOrders
owner: public(address)
domain: public(immutable(uint256))
trusted_books: public(HashMap[Book, bool])
current_nonce: public(uint256)
orders: public(HashMap[uint256, Order])
canceled_xorders: public(HashMap[uint256, uint256])

################################################################
#                Constructor & Admin Functions                 #
################################################################


@external
def __init__(_domain: uint256, _lzEndpoint: ILayerZeroEndpoint):
    """
    @dev Initializes the contract by setting the sender
         as the contract owner.
    @notice Only executed once when the contract is deployed.
    """
    self.owner = msg.sender
    self.lzEndpoint = _lzEndpoint
    domain = _domain

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

################################################################
#             On-Chain Order Management Functions              #
################################################################

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

################################################################
#                  Single-Book Order Filling                   #
################################################################

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
def fill_signed_order(
        order: Order,
        signature: Bytes[65]
):
    """
    @dev Fills an active signed order.
    @notice The maker of the order cannot fill it.
    @param order The order to be filled.
    @param signature The signature of the order.
    """
    assert self._check_order_signature(order, signature, order.maker), "Invalid signature"
    assert order.maker != msg.sender, "Cannot fill your own order"
    assert order.desired.transferFrom(msg.sender, order.maker, order.desired_amount, default_return_value=True), "Failed to transfer desired token"
    assert order.asset.transferFrom(order.maker, msg.sender, order.amount, default_return_value=True), "Failed to transfer asset token"
    log OrderFilled(order.maker, msg.sender, order.asset, order.amount, order.desired, order.desired_amount, order.nonce)

################################################################
#                      Remote Book Orders                      #
################################################################

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

################################################################
#                            Utils                             #
################################################################

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

################################################################
#                EIP712 SIGNATURE VERIFICATION                 #
################################################################

_DOMAIN_TYPEHASH: constant(bytes32) = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")

@view
@internal
def _hash_order(order: Order) -> bytes32:

    _DOMAIN_SEPARATOR: bytes32 = keccak256(
        _abi_encode(
            _DOMAIN_TYPEHASH,
            keccak256("Order"),
            keccak256("1.0"),
            chain.id,
            self
        )
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
            _DOMAIN_SEPARATOR,
            struct_hash))

@view
@internal
def _hash_xorder(order: XOrder) -> bytes32:

    _DOMAIN_SEPARATOR: bytes32 = keccak256(
        _abi_encode(
            _DOMAIN_TYPEHASH,
            keccak256("XOrder"),
            keccak256("1.0"),
            chain.id,
            self
        )
    )


    XORDER_TYPE_HASH: bytes32 = keccak256(
        "XOrder(uint256 source_domain,uint256 target_domain,address maker,address asset,uint256 amount,address desired,uint256 desired_amount,uint256 nonce)"
        )

    struct_hash: bytes32 = keccak256(
        _abi_encode(
            XORDER_TYPE_HASH,
            order.source_domain,
            order.target_domain,
            order.maker,
            order.asset.address,
            order.amount,
            order.desired.address,
            order.desired_amount,
            order.nonce
        )
        )

    return keccak256(
        concat(
            b"\x19\x01",
            _DOMAIN_SEPARATOR,
            struct_hash))


@view
@external
def check_order_signature(order: Order, signature: Bytes[65], signer: address) -> bool:
    """
    @dev Checks the signature of an order.
    @param order The Order struct to be signed.
    @param signature The signature of the order.
    @param signer The address of the signer.
    @return bool Whether the signature is valid or not.
    """
    return self._check_order_signature(order, signature, signer)

@view
@internal
def _check_order_signature(order: Order, signature: Bytes[65], signer: address) -> bool:
    # slice signature into v, r, s
    v: uint256 = convert(slice(signature, 0, 1), uint256)
    r: uint256 = convert(slice(signature, 1, 32), uint256)
    s: uint256 = convert(slice(signature, 33, 32), uint256)
    return ecrecover(self._hash_order(order), v, r, s) == signer


@view
@external
def check_xorder_signature(order: XOrder, signature: Bytes[65], signer: address) -> bool:
    """
    @dev Checks the signature of an order.
    @param order The Order struct to be signed.
    @param signature The signature of the order.
    @param signer The address of the signer.
    @return bool Whether the signature is valid or not.
    """
    return self._check_xorder_signature(order, signature, signer)

@view
@internal
def _check_xorder_signature(order: XOrder, signature: Bytes[65], signer: address) -> bool:
    # slice signature into v, r, s
    v: uint256 = convert(slice(signature, 0, 1), uint256)
    r: uint256 = convert(slice(signature, 1, 32), uint256)
    s: uint256 = convert(slice(signature, 33, 32), uint256)
    return ecrecover(self._hash_xorder(order), v, r, s) == signer

@view
@external
def validate_xorder(order: XOrder, signature: Bytes[65]) -> bool:
    return self._validate_xorder(order, signature)

@view
@internal
def _validate_xorder(order: XOrder, signature: Bytes[65]) -> bool:
    if not order.target_domain == domain:
        return False
    return self._check_xorder_signature(order, signature, order.maker)

################################################################
#                       NonBlockingLzApp                       #
################################################################

PAYLOAD_SIZE: constant(uint256) = 256
CONFIG_SIZE: constant(uint256) = 512

@internal
def _nonblockingLzReceive(_srcChainId: uint16, _srcAddress: Bytes[40], _nonce: uint64, _payload: Bytes[PAYLOAD_SIZE]):
    # contract body upon cross-chain call goes here
    pass

failedMessages: public(HashMap[uint16, HashMap[Bytes[40], HashMap[uint64, bytes32]]])

event MessageFailed:
    _srcChainId: uint16
    _srcAddress: Bytes[40]
    _nonce: uint64
    _payload: Bytes[PAYLOAD_SIZE]
    _reason: Bytes[1024]


event RetryMessageSuccess:
    _srcChainId: uint16
    _srcAddress: Bytes[40]
    _nonce: uint64
    _payloadHash: bytes32

# filler implementation of _blockingLzReceive
# body is just a `pass` statement
@internal
def _blockingLzReceive(_srcChainId: uint16, _srcAddress: Bytes[40], _nonce: uint64, _payload: Bytes[PAYLOAD_SIZE]):
    # call self via raw_call with revert_on_failure=False and max_outsize=256
    # raw_call signature is pasted below
    # raw_call(to: address, data: Bytes, max_outsize: int = 0, gas: uint256 = gasLeft, value: uint256 = 0, is_delegate_call: bool = False, is_static_call: bool = False, revert_on_failure: bool = True)→ Bytes[max_outsize]
    success: bool = False
    data: Bytes[256] = b""
    success, data = raw_call(self, concat(0x66ad5c8a, _abi_encode(_srcChainId, _srcAddress, _nonce, _payload)), max_outsize=256, revert_on_failure=False)
    if not success:
        self._storeFailedMessage(_srcChainId, _srcAddress, _nonce, _payload)

# implementation of _storeFailedMessage
@internal
def _storeFailedMessage(_srcChainId: uint16, _srcAddress: Bytes[40], _nonce: uint64, _payload: Bytes[PAYLOAD_SIZE]):
    payloadHash: bytes32 = keccak256(_payload)
    self.failedMessages[_srcChainId][_srcAddress][_nonce] = payloadHash
    log MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, convert("Failed to send payload", Bytes[100]))

@external
def nonblockingLzReceive(_srcChainId: uint16, _srcAddress: Bytes[40], _nonce: uint64, _payload: Bytes[PAYLOAD_SIZE]):
    assert msg.sender == self, "ONLYSELF"
    self._nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload)

interface ILayerZeroReceiver:
    def lzReceive(srcChainId: uint16, srcAddress: Bytes[40], nonce: uint64, payload: Bytes[PAYLOAD_SIZE]): nonpayable

interface ILayerZeroEndpoint:
    # def send(dstChainId: uint16, destination: Bytes[40], payload: Bytes[CONFIG_SIZE], refundAddress: address, zroPaymentAddress: address, adapterParams: Bytes[CONFIG_SIZE]): payable
    def receivePayload(srcChainId: uint16, srcAddress: Bytes[40], dstAddress: address, nonce: uint64, gasLimit: uint256, payload: Bytes[PAYLOAD_SIZE]): nonpayable
    def getInboundNonce(srcChainId: uint16, srcAddress: Bytes[40]) -> uint64: view
    def getOutboundNonce(dstChainId: uint16, srcAddress: address) -> uint64: view
    def estimateFees(dstChainId: uint16, userApplication: address, payload: Bytes[PAYLOAD_SIZE], payInZRO: bool, adapterParam: Bytes[CONFIG_SIZE]) -> (uint256, uint256): view
    def getChainId() -> uint16: view
    def retryPayload(srcChainId: uint16, srcAddress: Bytes[40], payload: Bytes[PAYLOAD_SIZE]): nonpayable
    def hasStoredPayload(srcChainId: uint16, srcAddress: Bytes[40]) -> bool: view
    def getSendLibraryAddress(userApplication: address) -> address: view
    def getReceiveLibraryAddress(userApplication: address) -> address: view
    def isSendingPayload() -> bool: view
    def isReceivingPayload() -> bool: view
    def getConfig(version: uint16, chainId: uint16, userApplication: address, configType: uint256) -> Bytes[CONFIG_SIZE]: view
    def getSendVersion(userApplication: address) -> uint16: view
    def getReceiveVersion(userApplication: address) -> uint16: view
    def setConfig(version: uint16, chainId: uint16, configType: uint256, config: Bytes[CONFIG_SIZE]): nonpayable
    def setSendVersion(version: uint16): nonpayable
    def setReceiveVersion(version: uint16): nonpayable
    def forceResumeReceive(srcChainId: uint16, srcAddress: Bytes[40]): nonpayable

interface ILayerZeroMessagingLibrary:
    # def send(_userApplication: address, _lastNonce: uint64, _chainId: uint16, _destination: Bytes[40], _payload: Bytes[CONFIG_SIZE], refundAddress: address, _zroPaymentAddress: address, _adapterParams: Bytes[CONFIG_SIZE]): payable
    def estimateFees(_chainId: uint16, _userApplication: address, _payload: Bytes[PAYLOAD_SIZE], _payInZRO: bool, _adapterParam: Bytes[CONFIG_SIZE]) -> (uint256, uint256): view
    def setConfig(_chainId: uint16, _userApplication: address, _configType: uint256, _config: Bytes[CONFIG_SIZE]): nonpayable
    def getConfig(_chainId: uint16, _userApplication: address, _configType: uint256) -> Bytes[CONFIG_SIZE]: view

interface ILayerZeroOracle:
    def getPrice(dstChainId: uint16, outboundProofType: uint16) -> uint256: view
    def notifyOracle(dstChainId: uint16, outboundProofType: uint16, outboundBlockConfirmations: uint64): nonpayable
    def isApproved(_address: address) -> bool: view

interface ILayerZeroRelayer:
    def getPrice(dstChainId: uint16, outboundProofType: uint16, userApplication: address, payloadSize: uint256, adapterParams: Bytes[CONFIG_SIZE]) -> uint256: view
    def notifyRelayer(dstChainId: uint16, outboundProofType: uint16, adapterParams: Bytes[CONFIG_SIZE]): nonpayable
    def isApproved(_address: address) -> bool: view

owner: address

lzEndpoint: public(ILayerZeroEndpoint)
DEFAULT_PAYLOAD_SIZE_LIMIT: constant(uint256) = 1000000
trustedRemoteLookup: public(HashMap[uint16, Bytes[40]])
payloadSizeLimitLookup: public(HashMap[uint16, uint256])
minDstGasLookup: public(HashMap[uint16, HashMap[uint16, uint256]])
precrime: public(address)

event SetPrecrime:
    precrime: address

event SetTrustedRemote:
    _remoteChainId: uint16
    _path: Bytes[40]

event SetTrustedRemoteAddress:
    _remoteChainId: uint16
    _remoteAddress: Bytes[20]

event SetMinDstGas:
    _dstChainId: uint16
    _type: uint16
    _minDstGas: uint256

@internal
def _onlyOwner():
    assert msg.sender == self.owner

@external
def lzReceive(_srcChainId: uint16, _srcAddress: Bytes[40], _nonce: uint64, _payload: Bytes[PAYLOAD_SIZE]):
    assert msg.sender == self.lzEndpoint.address
    trustedRemote: Bytes[40] = self.trustedRemoteLookup[_srcChainId]
    assert len(_srcAddress) == len(trustedRemote)
    assert len(trustedRemote) > 0
    assert keccak256(_srcAddress) == keccak256(trustedRemote)

    self._blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload)


@internal
def _lzSend(_dstChainId: uint16, _payload: Bytes[PAYLOAD_SIZE], _refundAddress: address, _zroPaymentAddress: address, _adapterParams: Bytes[CONFIG_SIZE], _nativeFee: uint256):
    trustedRemote: Bytes[40] = self.trustedRemoteLookup[_dstChainId]
    assert len(trustedRemote) != 0
    self._checkPayloadSize(_dstChainId, len(_payload))
    # usually, we would call the send function like this
    # self.lzEndpoint.send(_dstChainId, trustedRemote, _payload, _refundAddress, _zroPaymentAddress, _adapterParams, value=_nativeFee)
    #
    # the interface definition for this function in solidity is:
    #     function send(uint16 _dstChainId, bytes calldata _destination, bytes calldata _payload, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external payable;

    #
    # because send is a reserved keyword in Vyper, we have to use raw_call to call this function
    # we will use _abiEncode to encode the arguments to be passed

    # encode the arguments
    payload: Bytes[2404] = _abi_encode(_dstChainId, trustedRemote, _payload, _refundAddress, _zroPaymentAddress, _adapterParams, method_id=method_id("send(uint16,bytes,bytes,address,address,bytes)"))
    # call the function
    raw_call(self.lzEndpoint.address, payload, value=_nativeFee)


@external
def _checkGasLimit(_dstChainId: uint16, _type: uint16, _adapterParams: Bytes[CONFIG_SIZE], _extraGas: uint256):
    providedGasLimit: uint256 = self._getGasLimit(_adapterParams)
    minGasLimit: uint256 = self.minDstGasLookup[_dstChainId][_type] + _extraGas
    assert minGasLimit > 0, "LzApp: minGasLimit not set"
    assert providedGasLimit >= minGasLimit, "LzApp: gas limit is too low"


@internal
@pure
def _getGasLimit(_adapterParams: Bytes[CONFIG_SIZE]) -> uint256:
    assert len(_adapterParams) >= 34
    return convert(slice(_adapterParams, 34, 32), uint256)

@internal
def _checkPayloadSize(_dstChainId: uint16, _payloadSize: uint256):
    payloadSizeLimit: uint256 = self.payloadSizeLimitLookup[_dstChainId]
    if payloadSizeLimit == 0:
        payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT
    assert _payloadSize <= payloadSizeLimit, "LzApp: payload size is too large"

@external
def getConfig(_version: uint16, _chainId: uint16, _configType: uint256) -> Bytes[CONFIG_SIZE]:
    return self.lzEndpoint.getConfig(_version, _chainId, self, _configType)

@external
def setConfig(_version: uint16, _chainId: uint16, _configType: uint256, _config: Bytes[CONFIG_SIZE]):
    self._onlyOwner()
    self.lzEndpoint.setConfig(_version, _chainId, _configType, _config)

@external
def setSendVersion(_version: uint16):
    self._onlyOwner()
    self.lzEndpoint.setSendVersion(_version)

@external
def setReceiveVersion(_version: uint16):
    self._onlyOwner()
    self.lzEndpoint.setReceiveVersion(_version)

@external
def forceResumeReceive(_srcChainId: uint16, _srcAddress: Bytes[40]):
    self.lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress)

@external
def setTrustedRemote(_srcChainId: uint16, _path: Bytes[40]):
    self._onlyOwner()
    self.trustedRemoteLookup[_srcChainId] = _path
    log SetTrustedRemote(_srcChainId, _path)

@external
def setTrustedRemoteAddress(_remoteChainId: uint16, _remoteAddress: address):
    # convert address to bytes
    _remoteAddressBytes: Bytes[20] = slice(concat(b"", convert(_remoteAddress, bytes32)), 12, 20)
    selfAddrAsBytes: Bytes[20] = slice(concat(b"", convert(self, bytes32)), 12, 20)
    self.trustedRemoteLookup[_remoteChainId] = concat(_remoteAddressBytes, selfAddrAsBytes)
    log SetTrustedRemoteAddress(_remoteChainId, _remoteAddressBytes)

@external
@view
def getTrustedRemoteAddress(_remoteChainId: uint16) -> Bytes[20]:
    path: Bytes[40] = self.trustedRemoteLookup[_remoteChainId]
    assert len(path) != 0
    return slice(path, 0, 20)

@external
def setPrecrime(precrime: address):
    self._onlyOwner()
    self.precrime = precrime
    log SetPrecrime(precrime)

@external
def setMinDstGas(_dstChainId: uint16, _packetType: uint16, _minGas: uint256):
    self._onlyOwner()
    assert _minGas > 0, "LzApp: invalid minGas"
    self.minDstGasLookup[_dstChainId][_packetType] = _minGas
    log SetMinDstGas(_dstChainId, _packetType, _minGas)

@external
@view
def isTrustedRemote(_srcChainId: uint16, _srcAddress: Bytes[40]) -> bool:
    trustedSource: Bytes[40] = self.trustedRemoteLookup[_srcChainId]
    return keccak256(trustedSource) == keccak256(_srcAddress)
