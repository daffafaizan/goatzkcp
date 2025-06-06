// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IGoatZKCPJudge.sol";
import "./Config.sol";
import "./utils/ReentrancyGuard.sol";
import "./Groth16Core.sol";
import "./Events.sol";

contract GoatZKCPJudge is IGoatZKCPJudge, ReentrancyGuard, Config, Events {

    address public factory; // factory

    /// @notice variables set by the factory
    address public seller; // seller
    address public buyer; // buyer
    uint256 private price; // price

    /// @notice variables set by the buyer
    bytes32 public hashZ;

    /// @notice timestamps
    uint256 public t0;
    uint256 public t1;
    uint256 public t2;

    /// @notice status of the exchange
    ExchangeStatus public status;

    /// @notice Contract statuses
    enum ExchangeStatus {
        uninitialized,
        initialized,
        finished,
        expired
    }

    constructor() {
        factory = msg.sender;
    }

    /// @notice Factory initialize the contract
    function initialize(address _seller, address _buyer, uint256 _price) external {
        require(msg.sender == factory, 'GoatZKCP: only GoatZKCPFactory can initialize the contract');
        require(_seller != address(0), "GoatZKCP: invalid address.");
        require(_buyer != address(0), "GoatZKCP: invalid address.");
        factory = msg.sender;
        buyer = _buyer;
        seller = _seller;
        price = _price;

        // initialize contract status
        status = ExchangeStatus.uninitialized;
    }

    /// @notice Buyer initially start the exchange procedure
    function init(bytes32 _hashZ) payable nonReentrant external {
        require(msg.sender == buyer, "GoatZKCP: invalid initializer.");
        require(status == ExchangeStatus.uninitialized, "GoatZKCP: invalid contract status.");
        require(uint64(msg.value) >= price, "GoatZKCP: payment not enough.");

        // set Hash of Z
        hashZ = _hashZ;
        // set initialize timestamp
        t0 = block.timestamp;
        // update contract state
        status = ExchangeStatus.initialized;

        emit ExchangeInit(t0, _hashZ);
    }

    /// @notice Seller handout the proof and other information to verify
    function verify(bytes calldata proof, bytes32 k) nonReentrant external {
        require(msg.sender == seller, "GoatZKCP: invalid verify invoker.");
        require(status == ExchangeStatus.initialized, "GoatZKCP: invalid contract status.");
        t1 = block.timestamp;
        require(t1 <= t0 + LIMIT_TIME_TAU, "GoatZKCP: invalid verify because of time expired.");

        bool success = Groth16Core.verify();
        if(success) {
            // transfer payment to seller
            payable(seller).transfer(uint64(price));
            // update contract state
            status = ExchangeStatus.finished;

            emit ExchangeVerifySuccess(t1, proof, k);
            return;
        }

        emit ExchangeVerifyFail(t1);
    }

    /// @notice Contract refunds buyer if the exchange expired without valid proof
    function refund() nonReentrant external {
        require(msg.sender == buyer, "GoatZKCP: invalid refund invoker.");
        require(status == ExchangeStatus.initialized, "GoatZKCP: invalid contract status.");
        t2 = block.timestamp;
        require(t2 > t0 + LIMIT_TIME_TAU, "GoatZKCP: invalid refund operation.");
        // refund buyer
        payable(buyer).transfer(uint64(price));
        // update contract state
        status = ExchangeStatus.expired;

        emit ExchangeRefund(t2);
    }

    /// Return unshielded price callable only by seller or buyer
    function checkPrice() external view returns (uint64) {
        require(msg.sender == buyer || msg.sender == seller, 'GoatZKCP: only the buyer or the seller can check the price.');
        return uint64(price);
    }
}
