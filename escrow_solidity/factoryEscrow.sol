
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./escrow.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract EscrowFactory is OwnableUpgradeable {
    address private beacon;
    mapping(string => mapping(string => address)) private userInfo;

    /**
     * @dev Emitted when a new proxy address for Escrow's deployed.
     */
    event NewProxyAddress(address NewProxyAddress, string dealId);

    /**
     * @dev Throws if address passed is not a contract address.
     */
    modifier isContract(address _addr) {
        require(
            _addr.code.length != 0 && _addr != address(0),
            "Beacon address has to be a contract address!"
        );
        _;
    }

    /**
     * @dev Sets the address of initial implementation, and the contract's deployer as the
     * initial owner of the contract.
     */
    function initialize(address _beacon)
        public
        isContract(_beacon)
        initializer
    {
        __Ownable_init();
        beacon = _beacon;
    }

    /**
     * @dev Creates a beacon proxy, sets user's details and deposits ether into
     * the beacon proxy.
     *
     * Emits a {NewProxyAddress} event.
     */
    function createEscrowProxy(
        string memory _userId,
        string memory _dealId,
        address payable _commissionWallet,
        uint256 _minimumEscrowAmount,
        uint256 _commissionRate,
        address payable _buyer,
        address payable _seller
    ) external {
        BeaconProxy proxy = new BeaconProxy(
            beacon,
            abi.encodeWithSelector(
                Escrow.initializeDeal.selector,
                _commissionWallet,
                _minimumEscrowAmount,
                _commissionRate,
                owner()
            )
        );
        emit NewProxyAddress(address(proxy), _dealId);
        setUserDealDetails(_userId, _dealId, address(proxy));
        Escrow(address(proxy)).escrowParties(_buyer, _seller);
        // Escrow(address(proxy)).deposit{value: msg.value}();
    }

    /**
     * @dev Sets proxy contract address against the user's specific dealId.
     * Private function without access restriction.
     */
    function setUserDealDetails(
        string memory _userId,
        string memory _dealId,
        address _escrowAddress
    ) private {
        userInfo[_userId][_dealId] = _escrowAddress;
    }

    /**
     * @dev Returns proxy address of a particular user's deal.
     */
    function escrowProxyAddress(string memory _userId, string memory _dealId)
        public
        view
        returns (address)
    {
        return userInfo[_userId][_dealId];
    }

    /**
     * @dev Returns implementation address for a particular beacon.
     */
    function escrowImplAddress() public view returns (address) {
        return UpgradeableBeacon(beacon).implementation();
    }

    /**
     * @dev Returns beacon address to which proxy address's point to.
     */
    function escrowBeaconAddress() public view returns (address) {
        return beacon;
    }
}