/**
 *Submitted for verification at Etherscan.io on 2022-05-26
*/

pragma solidity 0.8.0;

contract Ownable {
    address public owner;

    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(owner);
        owner = address(0);
    }
}

abstract contract ERC20Basic {
    function totalSupply() public view virtual returns (uint256);

    function balanceOf(address who) public view virtual returns (uint256);

    function transfer(address to, uint256 value) public virtual returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

abstract contract ERC20 is ERC20Basic {
    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual returns (bool);

    function approve(address spender, uint256 value)
        public
        virtual
        returns (bool);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract TokenRecipient {
    event ReceivedEther(address indexed sender, uint256 amount);
    event ReceivedTokens(
        address indexed from,
        uint256 value,
        address indexed token,
        bytes extraData
    );

    /**
     * @dev Receive tokens and generate a log event
     * @param from Address from which to transfer tokens
     * @param value Amount of tokens to transfer
     * @param token Address of token
     * @param extraData Additional data to log
     */
    function receiveApproval(
        address from,
        uint256 value,
        address token,
        bytes calldata extraData
    ) public {
        ERC20 t = ERC20(token);
        require(t.transferFrom(from, address(this), value));
        emit ReceivedTokens(from, value, token, extraData);
    }

    /**
     * @dev Receive Ether and generate a log event
     */
    fallback() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}

contract ProxyRegistry is Ownable {
    /* DelegateProxy implementation contract. Must be initialized. */
    address public delegateProxyImplementation;

    /* Authenticated proxies by user. */
    mapping(address => OwnableDelegateProxy) public proxies;

    /* Contracts pending access. */
    mapping(address => uint256) public pending;

    /* Contracts allowed to call those proxies. */
    mapping(address => bool) public contracts;

    /* Delay period for adding an authenticated contract.
       This mitigates a particular class of potential attack on the Wyvern DAO (which owns this registry) - if at any point the value of assets held by proxy contracts exceeded the value of half the WYV supply (votes in the DAO),
       a malicious but rational attacker could buy half the Wyvern and grant themselves access to all the proxy contracts. A delay period renders this attack nonthreatening - given two weeks, if that happened, users would have
       plenty of time to notice and transfer their assets.
    */
    uint256 public DELAY_PERIOD = 2 weeks;

    /* Addresses allowed to call registerProxy.*/
    mapping(address => bool) public managers;

    modifier isManager() {
        require(managers[msg.sender] == true);
        _;
    }

    function addManager(address address_) external onlyOwner {
        managers[address_] = true;
    }

    function removerManger(address address_) external onlyOwner {
        require(address_ != owner);
        managers[address_] = false;
    }

    /**
     * Start the process to enable access for specified contract. Subject to delay period.
     *
     * @dev ProxyRegistry owner only
     * @param addr Address to which to grant permissions
     */
    function startGrantAuthentication(address addr) public onlyOwner {
        require(!contracts[addr] && pending[addr] == 0);
        pending[addr] = block.timestamp;
    }

    /**
     * End the process to nable access for specified contract after delay period has passed.
     *
     * @dev ProxyRegistry owner only
     * @param addr Address to which to grant permissions
     */
    function endGrantAuthentication(address addr) public onlyOwner {
        require(
            !contracts[addr] &&
                pending[addr] != 0 &&
                ((pending[addr] + DELAY_PERIOD) < block.timestamp)
        );
        pending[addr] = 0;
        contracts[addr] = true;
    }

    /**
     * Revoke access for specified contract. Can be done instantly.
     *
     * @dev ProxyRegistry owner only
     * @param addr Address of which to revoke permissions
     */

    function revokeAuthentication(address addr) public onlyOwner {
        contracts[addr] = false;
    }

    /**
     * Register a proxy contract with this registry
     *
     * @dev Must be called by the user which the proxy is for, creates a new AuthenticatedProxy
     * @return proxy
     */
    function registerProxy()
        public
        isManager
        returns (OwnableDelegateProxy proxy)
    {
        require(address(proxies[msg.sender]) == address(0));
        proxy = new OwnableDelegateProxy(
            msg.sender,
            delegateProxyImplementation,
            abi.encodeWithSignature(
                "initialize(address,address)",
                msg.sender,
                address(this)
            )
        );
        proxies[msg.sender] = proxy;
        return proxy;
    }
}

contract WyvernProxyRegistry is ProxyRegistry {
    string public constant name = "Project Wyvern Proxy Registry";

    /* Whether the initial auth address has been set. */
    bool public initialAddressSet = false;

    constructor() {
        managers[msg.sender] = true;
        delegateProxyImplementation = address(new AuthenticatedProxy());
    }

    /**
     * Grant authentication to the initial Exchange protocol contract
     *
     * @dev No delay, can only be called once - after that the standard registry process with a delay must be used
     * @param authAddress Address of the contract to grant authentication
     */
    function grantInitialAuthentication(address authAddress) public onlyOwner {
        require(!initialAddressSet);
        initialAddressSet = true;
        contracts[authAddress] = true;
    }
}

contract OwnedUpgradeabilityStorage {
    // Current implementation
    address internal _implementation;

    // Owner of the contract
    address private _upgradeabilityOwner;

    /**
     * @dev Tells the address of the owner
     * @return the address of the owner
     */
    function upgradeabilityOwner() public view returns (address) {
        return _upgradeabilityOwner;
    }

    /**
     * @dev Sets the address of the owner
     */
    function setUpgradeabilityOwner(address newUpgradeabilityOwner) internal {
        _upgradeabilityOwner = newUpgradeabilityOwner;
    }

    /**
     * @dev Tells the address of the current implementation
     * @return address of the current implementation
     */
    function implementation() public view returns (address) {
        return _implementation;
    }

    /**
     * @dev Tells the proxy type (EIP 897)
     * @return proxyTypeId type, 2 for forwarding proxy
     */
    function proxyType() public pure returns (uint256 proxyTypeId) {
        return 2;
    }
}

contract AuthenticatedProxy is TokenRecipient, OwnedUpgradeabilityStorage {
    /* Whether initialized. */
    bool initialized = false;

    /* Address which owns this proxy. */
    address public user;

    /* Associated registry with contract authentication information. */
    ProxyRegistry public registry;

    /* Whether access has been revoked. */
    bool public revoked;

    /* Delegate call could be used to atomically transfer multiple assets owned by the proxy contract with one order. */
    enum HowToCall {
        Call,
        DelegateCall
    }

    /* Event fired when the proxy access is revoked or unrevoked. */
    event Revoked(bool revoked);

    /**
     * Initialize an AuthenticatedProxy
     *
     * @param addrUser Address of user on whose behalf this proxy will act
     * @param addrRegistry Address of ProxyRegistry contract which will manage this proxy
     */
    function initialize(address addrUser, ProxyRegistry addrRegistry) public {
        require(!initialized);
        initialized = true;
        user = addrUser;
        registry = addrRegistry;
    }

    /**
     * Set the revoked flag (allows a user to revoke ProxyRegistry access)
     *
     * @dev Can be called by the user only
     * @param revoke Whether or not to revoke access
     */
    function setRevoke(bool revoke) public {
        require(msg.sender == user);
        revoked = revoke;
        emit Revoked(revoke);
    }

    /**
     * Execute a message call from the proxy contract
     *
     * @dev Can be called by the user, or by a contract authorized by the registry as long as the user has not revoked access
     * @param dest Address to which the call will be sent
     * @param howToCall Which kind of call to make
     * @param _calldata Calldata to send
     * @return result of the call (success or failure)
     */
    function proxy(
        address dest,
        HowToCall howToCall,
        bytes calldata _calldata
    ) public returns (bool result) {
        require(
            msg.sender == user || (!revoked && registry.contracts(msg.sender))
        );
        if (howToCall == HowToCall.Call) {
            (bool result, ) = dest.call(_calldata);
        } else if (howToCall == HowToCall.DelegateCall) {
            (bool result, ) = dest.delegatecall(_calldata);
        }
        return result;
    }

    /**
     * Execute a message call and assert success
     *
     * @dev Same functionality as `proxy`, just asserts the return value
     * @param dest Address to which the call will be sent
     * @param howToCall What kind of call to make
     * @param _calldata Calldata to send
     */
    function proxyAssert(
        address dest,
        HowToCall howToCall,
        bytes calldata _calldata
    ) public {
        require(proxy(dest, howToCall, _calldata));
    }
}

abstract contract Proxy is OwnedUpgradeabilityStorage {
    /**
     * @dev Fallback function allowing to perform a delegatecall to the given implementation.
     * This function will return whatever the implementation call returns
     */
    fallback() external payable {
        address _impl = implementation();
        require(_impl != address(0));

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }
}

contract OwnedUpgradeabilityProxy is Proxy {
    /**
     * @dev Event to show ownership has been transferred
     * @param previousOwner representing the address of the previous owner
     * @param newOwner representing the address of the new owner
     */
    event ProxyOwnershipTransferred(address previousOwner, address newOwner);

    /**
     * @dev This event will be emitted every time the implementation gets upgraded
     * @param implementation representing the address of the upgraded implementation
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Upgrades the implementation address
     * @param implementation representing the address of the new implementation to be set
     */
    function _upgradeTo(address implementation) internal {
        require(_implementation != implementation);
        _implementation = implementation;
        emit Upgraded(implementation);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyProxyOwner() {
        require(msg.sender == proxyOwner());
        _;
    }

    /**
     * @dev Tells the address of the proxy owner
     * @return the address of the proxy owner
     */
    function proxyOwner() public view returns (address) {
        return upgradeabilityOwner();
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferProxyOwnership(address newOwner) public onlyProxyOwner {
        require(newOwner != address(0));
        emit ProxyOwnershipTransferred(proxyOwner(), newOwner);
        setUpgradeabilityOwner(newOwner);
    }

    /**
     * @dev Allows the upgradeability owner to upgrade the current implementation of the proxy.
     * @param implementation representing the address of the new implementation to be set.
     */
    function upgradeTo(address implementation) public onlyProxyOwner {
        _upgradeTo(implementation);
    }

    /**
     * @dev Allows the upgradeability owner to upgrade the current implementation of the proxy
     * and delegatecall the new implementation for initialization.
     * @param implementation representing the address of the new implementation to be set.
     * @param data represents the msg.data to bet sent in the low level call. This parameter may include the function
     * signature of the implementation to be called with the needed payload
     */
    function upgradeToAndCall(address implementation, bytes calldata data)
        public
        payable
        onlyProxyOwner
    {
        upgradeTo(implementation);
        // require(address(this).delegatecall(data));
    }
}

contract OwnableDelegateProxy is OwnedUpgradeabilityProxy {
    constructor(
        address owner,
        address initialImplementation,
        bytes memory _calldata
    ) public {
        setUpgradeabilityOwner(owner);
        _upgradeTo(initialImplementation);
        // require(initialImplementation.delegatecall(_calldata));
    }
}