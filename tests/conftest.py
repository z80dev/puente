import pytest

# define fixture for tokens
@pytest.fixture
def tokens(project, deployer, accounts):
    tokens = []

    # iterate from A to J and deploy a token for each
    for i in range(5):
        tokens.append(project.Token.deploy("100000000 ether", chr(65 + i), chr(65 + i), sender=deployer))
    for recipient in accounts[1:5]:
        for token in tokens:
            token.transfer(recipient, "100 ether", sender=deployer)
    return tokens

@pytest.fixture
def deployer(accounts):
    return accounts[0]

@pytest.fixture
def maker(accounts):
    return accounts[1]

@pytest.fixture
def taker(accounts):
    return accounts[2]

@pytest.fixture
def turtle(accounts):
    return accounts[3]

@pytest.fixture
def books(project, deployer):
    bookA = project.Book.deploy(1, sender=deployer)
    bookB = project.Book.deploy(2, sender=deployer)
    bookA.add_trusted_book(bookB, sender=deployer)
    bookB.add_trusted_book(bookA, sender=deployer)
    return [bookA, bookB]

# define fixture for book contract
@pytest.fixture
def book(project, deployer):
    return project.Book.deploy(0, sender=deployer)

@pytest.fixture
def lz_mock(accounts, project):
    lz_mock = project.EndpointMock.deploy(101, sender=accounts[0])
    return lz_mock
