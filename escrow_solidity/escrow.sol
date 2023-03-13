// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

contract Escrow {
    address payable public owner;
    address payable private commissionWallet;
    address payable public buyer;
    address payable public seller;

    uint256 private minimumEscrowAmount;
    uint256 private commissionRate;
    uint256 private depositTime;

    enum State {
        INIT,
        FUNDED,
        ACCEPTED,
        RELEASED,
        REFUNDED,
        WITHDRAWN_BY_OWNER
    }

    State private currentState;

    event Funded(address escrowWallet);
    event Accepted(address escrowWallet, address seller);
    event ReleaseFund(
        address released_by,
        address escrowWallet,
        uint256 amount_released,
        uint256 commission_amount
    );
    event Withdraw(
        address _buyer,
        address escrowWallet,
        uint256 amount_withdrawn,
        uint256 commission_amount
    );
    event SixMonths(
        address _destAddr,
        address escrowWallet,
        uint256 amount_withdrawn
    );

    modifier isAddressValid(address addr) {
        require(
            addr.code.length == 0 && addr != address(0x0),
            "Escrow: Invalid address!"
        );
        _;
    }

    modifier buyerOnly(address addr) {
        require(addr == buyer, "Escrow: Only accessible by buyer!");
        _;
    }

    modifier notOwner() {
        require(msg.sender != owner, "Escrow: Not accessible by owner!");
        _;
    }

    modifier notCommissionWallet(address addr) {
        require(
            addr != commissionWallet,
            "Escrow: Can not be commission wallet!"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Escrow: Only accessible by owner!");
        _;
    }

    modifier onlyBuyerOrSeller() {
        require(
            msg.sender == buyer || msg.sender == seller,
            "Escrow: Only accessible by buyer or seller!"
        );
        _;
    }

    modifier initCheck() {
        require(
            owner == address(0x0),
            "Escrow: Can not initialize a deal twice!"
        );
        _;
    }

    modifier stateInit() {
        require(
            currentState == State.INIT,
            "Escrow: Deal state is no longer INIT!"
        );
        _;
    }

    modifier stateFunded() {
        require(
            currentState == State.FUNDED,
            "Escrow: Deal state is no longer FUNDED!"
        );
        _;
    }

    modifier stateAccepted() {
        require(
            currentState == State.ACCEPTED,
            "Escrow: Deal state is no longer ACCEPTED!"
        );
        _;
    }

    modifier minimumAmount() {
        require(
            msg.value >= minimumEscrowAmount,
            "Escrow: Value less than minimum amount required!"
        );
        _;
    }

    modifier distinctAddresses(address _addr1, address _addr2) {
        require(_addr1 != _addr2, "Escrow: Addresses can not be the same!");
        _;
    }

    modifier minimumTimePeriod() {
        require(
            block.timestamp - depositTime > 26 weeks,
            "Funds can be withdrawn only after a period of 6 months!"
        );
        _;
    }

    function initialize(
        address payable _commissionWallet,
        uint256 _minimumEscrowAmount,
        uint256 _commissionRate,
        address payable _owner,
        address payable _buyer
    )
        public
        initCheck
        isAddressValid(_commissionWallet)
        distinctAddresses(_buyer, owner)
        notCommissionWallet(_owner)
        notCommissionWallet(_buyer)
    {
        commissionWallet = _commissionWallet;
        minimumEscrowAmount = _minimumEscrowAmount;
        commissionRate = _commissionRate;
        owner = _owner;
        buyer = payable(_buyer);
    }

    function deposit(address _buyer)
        public
        payable
        stateInit
        buyerOnly(_buyer)
        minimumAmount
    {
        currentState = State.FUNDED;
        emit Funded(address(this));
        depositTime = block.timestamp;
    }

    function acceptDeal()
        public
        notOwner
        stateFunded
        distinctAddresses(buyer, msg.sender)
        notCommissionWallet(msg.sender)
    {
        seller = payable(msg.sender);
        currentState = State.ACCEPTED;
        emit Accepted(address(this), seller);
    }

    function releaseFund() public stateAccepted onlyBuyerOrSeller {
        (
            uint256 amountAfterCommission,
            uint256 commissionAmount
        ) = calculateAmountToTransfer();
        msg.sender == buyer
            ? seller.transfer(amountAfterCommission)
            : buyer.transfer(amountAfterCommission);
        commissionWallet.transfer(commissionAmount);
        currentState = State.RELEASED;
        emit ReleaseFund(
            msg.sender,
            address(this),
            amountAfterCommission,
            commissionAmount
        );
    }

    function withdrawFund() public stateFunded buyerOnly(msg.sender) {
        (
            uint256 amountAfterCommission,
            uint256 commissionAmount
        ) = calculateAmountToTransfer();
        buyer.transfer(amountAfterCommission);
        commissionWallet.transfer(commissionAmount);
        currentState = State.REFUNDED;
        emit Withdraw(
            msg.sender,
            address(this),
            amountAfterCommission,
            commissionAmount
        );
    }

    function calculateAmountToTransfer()
        internal
        view
        returns (uint256, uint256)
    {
        uint256 dealAmount = address(this).balance;
        uint256 amountAfterCommission = dealAmount -
            ((dealAmount * commissionRate) / 100);
        uint256 commissionAmount = dealAmount - amountAfterCommission;
        return (amountAfterCommission, commissionAmount);
    }

    function postSixMonths() public onlyOwner stateAccepted minimumTimePeriod {
        uint256 contractBalance = address(this).balance;
        owner.transfer(contractBalance);
        currentState = State.WITHDRAWN_BY_OWNER;
        emit SixMonths(owner, address(this), contractBalance);
    }

    function currentStateOfDeal() public view returns (State) {
        return currentState;
    }

    function commissionRateOfDeal() public view returns (uint256) {
        return commissionRate;
    }
}
