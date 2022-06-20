pragma solidity >=0.6.0 <0.8.0;

import "./library/SafeMath.sol";
import "./StakingReward.sol";
import "./IValidtors.sol";

contract Timer is StakingReward {
    using SafeMath for uint256;
    // System contracts
    address public constant ValidatorContractAddr =
        0x000000000000000000000000000000000000f000;
    struct Description {
        string moniker;
        string identity;
        string website;
        string email;
        string details;
    }

    struct Validator {
        address payable feeAddr;
        Status status;
        uint256 coins;
        Description description;
        uint256 hbIncoming;
        uint256 totalJailedHB;
        uint256 lastWithdrawProfitsBlock;
        // Address list of user who has staked for this validator
        address[] stakers;
    }

    struct StakingInfo {
        uint256 coins;
        // unstakeBlock != 0 means that you are unstaking your stake, so you can't
        // stake or unstake
        uint256 unstakeBlock;
        // index of the staker list in validator
        uint256 index;
    }

    //blockHeight to ActiveValidatorSet
    mapping(uint256 => address[]) blockHeight2ActiveValidatorSet;
    //blockHeight to HighestValidatorsSet
    mapping(uint256 => address[]) blockHeight2HighestValidatorsSet;
    // current validator set used by chain
    // only changed at block epoch
    uint256[] public validatorSetBlockHeight;
    // highest validator set(dynamic changed)
    address[] public highestValidatorsSet;
    // total stake of all validators
    uint256 public totalStake;
    // total jailed hb
    uint256 public startBlockHeight;
    uint256 public latestExtraRewardBlockHeight;
    uint256 public latestSyncBlockHeight;

    constructor() public {
        validatorsContract = IValidators(ValidatorContractAddr);
    }

    function update(uint256 blockHeight, address[] calldata vals) external {
        uint256 bh = blockHeight > 0 ? blockHeight : block.number;
        if (validatorSetBlockHeight.length == 0) {
            startBlockHeight = bh;
            validatorSetBlockHeight.push(bh);
            blockHeight2ActiveValidatorSet[bh] = validatorsContract
                .getTopValidators();
            blockHeight2ActiveValidatorSet[bh] = validatorsContract
                .getActiveValidators();
        } else {
            address[] cvals = blockHeight2HighestValidatorsSet[
                validatorSetBlockHeight[validatorSetBlockHeight.length - 1]
            ];

            for (uint256 i = 0; i < vals.length; i++) {
                require(vals[i] != address(0), "Invalid validator address");
                bool diff = true;
                for (uint256 j = 0; j < cvals.length; j++) {
                    if (vals == vals[i]) {
                        diff = false;
                        break;
                    }
                }

                if (diff) {
                    validatorSetBlockHeight.push(bh);
                    blockHeight2ActiveValidatorSet[bh] = validatorsContract
                        .getTopValidators();
                    blockHeight2ActiveValidatorSet[bh] = validatorsContract
                        .getActiveValidators();
                    break;
                }
            }
        }
        if (latestExtraRewardBlockHeight + 1200 + 800 < block.number) {
           reward();
        }
        latestSyncBlockHeight = block.number;
    }

    function reward() private {
            uint256 end = latestExtraRewardBlockHeight + 1200;
            uint256[] memory topvalsupdateblockHeight = new uint256[](1);
            uint256 j = 0;
            for (uint256 i = 0; i < validatorSetBlockHeight.length; i++) {
                if (
                    validatorSetBlockHeight[i] > latestExtraRewardBlockHeight &&
                    validatorSetBlockHeight[i] < end
                ) {
                    topvalsupdateblockHeight.push(validatorSetBlockHeight[i]);
                } else if (
                    validatorSetBlockHeight[i] < latestExtraRewardBlockHeight
                ) {
                    j = i;
                }
            }
            if (topvalsupdateblockHeight.length == 1) {
                require(
                    validatorSetBlockHeight.length > 0,
                    "validatorSetBlockHeight is empty"
                );
                topvalsupdateblockHeight.push(
                    validatorSetBlockHeight[validatorSetBlockHeight.length - 1]
                );
                address[] cvals = blockHeight2HighestValidatorsSet[
                    validatorSetBlockHeight[validatorSetBlockHeight.length - 1]
                ];
                distributeBlockReward(1200, cvals);
            } else {
                topvalsupdateblockHeight[0] = validatorSetBlockHeight[j];
                topvalsupdateblockHeight.push(
                    latestExtraRewardBlockHeight + 1200
                );
                uint256 pre = latestExtraRewardBlockHeight;
                for (uint256 k = 1; k < topvalsupdateblockHeight.length; k++) {
                    uint256 blocks = topvalsupdateblockHeight[k] - pre;
                    address[] cvals = blockHeight2HighestValidatorsSet[
                        topvalsupdateblockHeight[k - 1]
                    ];
                    if (blocks > 0) {
                        distributeBlockReward(
                            pre,
                            topvalsupdateblockHeight[k],
                            blocks,
                            cvals
                        );
                    }
                    pre = topvalsupdateblockHeight[k];
                }
            }
            clear(j);
            latestExtraRewardBlockHeight += 1200;
    }

    function clear(uint256 j) private {
        //clear
        uint256[] memory tmp = new uint256[](0);
        for (uint256 k = j; k < validatorSetBlockHeight.length; k++) {
            tmp.push(validatorSetBlockHeight[k]);
        }
        for (uint256 k = 0; k < j; k++) {
            blockHeight2HighestValidatorsSet[validatorSetBlockHeight[k]] = [];
            if (k < tmp.length) {
                validatorSetBlockHeight[k] = tmp[k];
            }
        }
        if (j < tmp.length) {
            for (uint256 k = j; k < tmp.length; k++) {
                validatorSetBlockHeight[k] = tmp[k];
            }
        }
        while (validatorSetBlockHeight.length > tmp.length) {
            validatorSetBlockHeight.pop();
        }
    }
}
