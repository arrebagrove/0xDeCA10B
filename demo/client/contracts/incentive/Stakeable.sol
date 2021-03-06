pragma solidity ^0.5.0;

import "../libs/Math.sol";
import "../libs/SafeMath.sol";
import "../libs/SignedSafeMath.sol";

import {IncentiveMechanism, IncentiveMechanism64} from "./IncentiveMechanism.sol";
import {Ownable} from "../ownership/Ownable.sol";

/**
 * A base class for contracts that want to accept deposits to incentivise good contributions of information.
 */
contract Stakeable is Ownable, IncentiveMechanism {
    using SafeMath for uint256;

    // The following members are in chronologically increasing order of when they should occur.
    /**
     * Amount of time to wait to get a refund back.
     * Once this amount of time has passed, the entire deposit can be reclaimed.
     * Also once this amount of time has passed, the deposit (in full or in part) can be taken by others.
     */
    uint32 public refundWaitTimeS;

    /**
     * Amount of time owner has to wait to take someone's entire remaining refund.
     * The purpose of this is to give the owner some incentive to deploy a model.
     * This must be greater than the required amount of time to wait for attempting a refund.
     * Contracts may want to enforce that this is much greater than the amount of time to wait for attempting a refund
     * to give even more time to get the deposit back and not let the owner take too much.
     */
    uint32 public ownerClaimWaitTimeS;

    /**
     * Amount of time after which anyone can take someone's entire remaining refund.
     * Similar to `ownerClaimWaitTimeS` but it allows any address to claim funds for specific data.
     * The purpose of this is to help ensure that value does not get "stuck" in a contract.
     * This must be greater than the required amount of time to wait for attempting a refund.
     * Contracts may want to enforce that this is much greater than the amount of time to wait for attempting a refund
     * to give even more time to get the deposit back and not let others take too much.
     */
    uint32 public anyAddressClaimWaitTimeS;
    // End claim time members.

    /**
     * Multiplicative factor for the cost calculation.
     */
    uint public costWeight;

    /**
     * The last time that data was updated in seconds since the epoch.
     */
    uint public lastUpdateTimeS;

    /**
     * The number of samples that have been determined to be good for each address.
     */
    mapping(address => uint128) public numGoodDataPerAddress;

    /**
     * The total number of samples that have been determined to be good.
     */
    uint128 public totalGoodDataCount = 0;

    constructor(
        // Parameters in chronological order.
        uint32 _refundWaitTimeS,
        uint32 _ownerClaimWaitTimeS,
        uint32 _anyAddressClaimWaitTimeS,
        uint80 _costWeight
    ) Ownable() public {
        require(_refundWaitTimeS <= _ownerClaimWaitTimeS, "Owner claim wait time must be at least the refund wait time.");
        require(_ownerClaimWaitTimeS <= _anyAddressClaimWaitTimeS, "Owner claim wait time must be less than the any address claim wait time.");

        refundWaitTimeS = _refundWaitTimeS;
        ownerClaimWaitTimeS = _ownerClaimWaitTimeS;
        anyAddressClaimWaitTimeS = _anyAddressClaimWaitTimeS;
        costWeight = _costWeight;

        lastUpdateTimeS = now; // solium-disable-line security/no-block-members
    }

    /**
     * @return The amount of wei required to add data now.
     *
     * Note that since `now` depends on the last block time,
     * when testing, the output of this function may not change over time unless blocks are created.
     */
    function getNextAddDataCost() public view returns (uint) {
        // Value sent is in wei (1E18 wei = 1 ether).
        require(lastUpdateTimeS <= now, "The last update time is after the current time."); // solium-disable-line security/no-block-members
        // No SafeMath check needed because already done above.
        uint divisor = now - lastUpdateTimeS; // solium-disable-line security/no-block-members
        if (divisor == 0) {
            divisor = 1;
        } else {
            divisor = Math.sqrt(divisor);
            // TODO Check that sqrt is "safe".
        }
        return costWeight.mul(1 hours).div(divisor);
    }
}

contract Stakeable64 is IncentiveMechanism64, Stakeable {

    using SafeMath for uint256;
    using SignedSafeMath for int256;

    constructor(
        uint32 _refundWaitTimeS,
        uint32 _ownerClaimWaitTimeS,
        uint32 _anyAddressClaimWaitTimeS,
        uint80 _costWeight
    ) Stakeable(_refundWaitTimeS, _ownerClaimWaitTimeS, _anyAddressClaimWaitTimeS, _costWeight) public {
        // solium-disable-previous-line no-empty-blocks
    }

    function handleAddData(uint msgValue, int64[] memory data, uint64 classification) public onlyOwner returns (uint cost) {
        cost = getNextAddDataCost(data, classification);
        require(msgValue >= cost, "Didn't pay enough.");
        lastUpdateTimeS = now; // solium-disable-line security/no-block-members
    }

    function handleRefund(
        address submitter,
        int64[] memory /* data */, uint64 classification,
        uint addedTime,
        uint claimableAmount, bool claimedBySubmitter,
        uint64 prediction)
        public onlyOwner
        returns (uint refundAmount) {
        refundAmount = claimableAmount;

        // Make sure deposit can be taken.
        require(!claimedBySubmitter, "Deposit already claimed by submitter.");
        require(refundAmount > 0, "There is no reward left to claim.");
        require(now - addedTime >= refundWaitTimeS, "Not enough time has passed."); // solium-disable-line security/no-block-members
        require(prediction == classification, "The model doesn't agree with your contribution.");

        numGoodDataPerAddress[submitter] += 1;
        totalGoodDataCount += 1;
    }

    function handleReport(
        address reporter,
        int64[] memory /* data */, uint64 classification,
        uint addedTime, address originalAuthor,
        uint initialDeposit, uint claimableAmount, bool claimedByReporter,
        uint64 prediction)
        public onlyOwner
        returns (uint rewardAmount) {
        // Make sure deposit can be taken.

        require(claimableAmount > 0, "There is no reward left to claim.");
        uint timeSinceAddedS = now - addedTime; // solium-disable-line security/no-block-members
        if (timeSinceAddedS >= ownerClaimWaitTimeS && reporter == owner) {
            rewardAmount = claimableAmount;
        } else if (timeSinceAddedS >= anyAddressClaimWaitTimeS) {
            // Enough time has passed, give the entire remaining deposit to the reporter.
            rewardAmount = claimableAmount;
        } else {
            // Don't allow someone to claim back their own deposit if their data was wrong.
            // They can still claim it from another address but they will have had to have sent good data from that address.
            require(reporter != originalAuthor, "Cannot take your own deposit. Ask for a refund instead.");

            require(!claimedByReporter, "Deposit already claimed by reporter.");
            require(timeSinceAddedS >= refundWaitTimeS, "Not enough time has passed.");
            require(prediction != classification, "The model should not agree with the contribution.");

            uint numGoodForReporter = numGoodDataPerAddress[reporter];
            require(numGoodForReporter > 0, "The sender has not sent any good data.");
            // Weight the reward by the proportion of good data sent (maybe square the resulting value).
            // One nice reason to do this is to discourage someone from adding bad data through one address
            // and then just using another address to get their full deposit back.
            rewardAmount = initialDeposit.mul(numGoodForReporter).div(totalGoodDataCount);
            if (rewardAmount == 0 || rewardAmount > claimableAmount) {
                // There is too little left to divide up. Just give everything to this reporter.
                rewardAmount = claimableAmount;
            }
        }
    }
}
