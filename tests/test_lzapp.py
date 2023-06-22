import ape
import pytest
from eth_abi.packed import encode_packed
# import ipython to embed
import IPython

@pytest.fixture
def lz_mock(accounts, project):
    lz_mock = project.EndpointMock.deploy(101, sender=accounts[0])
    return lz_mock

def test_omnicounter(lz_mock, project, accounts):
    lzapp = project.OmniCounter.deploy(lz_mock, sender=accounts[0])
    lzapp2 = project.OmniCounter.deploy(lz_mock, sender=accounts[0])
    assert lzapp.lzEndpoint() == lz_mock.address
    lz_mock.setDestLzEndpoint(lzapp.address, lz_mock.address, sender=accounts[0])
    lz_mock.setDestLzEndpoint(lzapp2.address, lz_mock.address, sender=accounts[0])
    path = encode_packed(['address', 'address'], [lzapp2.address, lzapp.address])
    path2 = encode_packed(['address', 'address'], [lzapp.address, lzapp2.address])
    lzapp.setTrustedRemote(101, path, sender=accounts[0])
    lzapp2.setTrustedRemote(101, path2, sender=accounts[0])
    # lzapp.setTrustedRemoteAddress(101, lzapp.address, sender=accounts[0])
    # embed to debug
    # IPython.embed()
    # print trusted remote address in hex
    assert lzapp.getTrustedRemoteAddress(101).hex() == '0x' + bytes.fromhex(lzapp2.address[2:]).hex()

    r = lzapp.incrementCounter(101, sender=accounts[0], value=1000000000000000000)
    assert lzapp2.counter() == 1


def test_omnisetter(lz_mock, project, accounts):
    lzapp = project.OmniSetter.deploy(lz_mock, sender=accounts[0])
    lzapp2 = project.OmniSetter.deploy(lz_mock, sender=accounts[0])
    assert lzapp.lzEndpoint() == lz_mock.address
    lz_mock.setDestLzEndpoint(lzapp.address, lz_mock.address, sender=accounts[0])
    lz_mock.setDestLzEndpoint(lzapp2.address, lz_mock.address, sender=accounts[0])
    path = encode_packed(['address', 'address'], [lzapp2.address, lzapp.address])
    path2 = encode_packed(['address', 'address'], [lzapp.address, lzapp2.address])
    lzapp.setTrustedRemote(101, path, sender=accounts[0])
    lzapp2.setTrustedRemote(101, path2, sender=accounts[0])
    # lzapp.setTrustedRemoteAddress(101, lzapp.address, sender=accounts[0])
    # embed to debug
    # IPython.embed()
    # print trusted remote address in hex
    assert lzapp.getTrustedRemoteAddress(101).hex() == '0x' + bytes.fromhex(lzapp2.address[2:]).hex()

    r = lzapp.incrementCounter(101, 5, sender=accounts[0], value=1000000000000000000)
    assert lzapp2.counter() == 5
