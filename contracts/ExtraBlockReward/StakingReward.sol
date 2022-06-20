pragma solidity >=0.6.0 <0.8.0;

import "./library/SafeMath.sol";
import "./IValidtors.sol";
// 31536000blocks/year;

// Reward Pool
// 6,250,000 5,000,000 3,750,000

// SRD1=totalSRD *(1-20)%*50%/Y*(TV +x%*TD)/(TV +TD)+totalSRD *80%*50%* (TV + x% * TD))/ total TV^
// NRD1= totalSRD * (1-20)% * 50% * TAN / (𝑡𝑜𝑡𝑎𝑙 TV ^+ total TD )
// DRD1 =totalSRD *80%*50%/Y*(1-x)%*TD1 /(TV +TD)+totalSRD *80%*50%*
// (1-x)% * TD1 / (𝑡𝑜𝑡𝑎𝑙 TV ^+ total TD )
// SRD1= Daily single validator Staking𝑅ewards totalSRD= total daily Staking𝑅𝑒𝑤𝑎𝑟𝑑s Y=Number of Validators
// x=the percentage of commission TV=validation staked tokens
// TD=validation delegated tokens
// NRD1=Daily single alternative node rewards
// TAN=alternative node staked tokens
// DRD1= Daily single Delegator 𝑅ewards
// ^ Total validators staked token include these from alternative nodes;

pragma solidity >=0.6.0 <0.8.0;

import "./library/SafeMath.sol";

contract StakingReward {
    using SafeMath for uint256;
    uint256 constant ONE = 10**18;
uint256 constant FIRST = 6250000*ONE;
uint256 constant SECOND = 5000000*ONE;
uint256 constant THIRD =  3750000*ONE;
    enum Status {
        // validator not exist, default status
        NotExist,
        // validator created
        Created,
        // anyone has staked for the validator
        Staked,
        // validator's staked coins < MinimalStakingCoin
        Unstaked,
        // validator is jailed by system(validator have to repropose)
        Jailed
    }

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

    mapping(address => Validator) validatorInfo;
    // staker => validator => info
    mapping(address => mapping(address => StakingInfo)) staked;
    // current validator set used by chain
    // only changed at block epoch
    address[] public currentValidatorSet;
    // highest validator set(dynamic changed)
    address[] public highestValidatorsSet;
    // total stake of all validators
    uint256 public totalStake;
    // total jailed hb
    uint256 public totalJailedHB;
    IValidators validatorsContract;
    // System contracts
    Proposal proposal;
    Punish punish;

    enum Operations {
        Distribute,
        UpdateValidators
    }
    // Record the operations is done or not.
    mapping(uint256 => mapping(uint8 => bool)) operationsDone;

    event LogCreateValidator(
        address indexed val,
        address indexed fee,
        uint256 time
    );
    event LogEditValidator(
        address indexed val,
        address indexed fee,
        uint256 time
    );
    event LogReactive(address indexed val, uint256 time);
    event LogAddToTopValidators(address indexed val, uint256 time);
    event LogRemoveFromTopValidators(address indexed val, uint256 time);
    event LogUnstake(
        address indexed staker,
        address indexed val,
        uint256 amount,
        uint256 time
    );
    event LogWithdrawStaking(
        address indexed staker,
        address indexed val,
        uint256 amount,
        uint256 time
    );
    event LogWithdrawProfits(
        address indexed val,
        address indexed fee,
        uint256 hb,
        uint256 time
    );
    event LogRemoveValidator(address indexed val, uint256 hb, uint256 time);
    event LogRemoveValidatorIncoming(
        address indexed val,
        uint256 hb,
        uint256 time
    );
    event LogDistributeBlockReward(
        address indexed coinbase,
        uint256 blockReward,
        uint256 time
    );
    event LogUpdateValidator(address[] newSet);
    event LogStake(
        address indexed staker,
        address indexed val,
        uint256 staking,
        uint256 time
    );

    modifier onlyNotRewarded() {
        require(
            operationsDone[block.number][uint8(Operations.Distribute)] == false,
            "Block is already rewarded"
        );
        _;
    }

    modifier onlyNotUpdated() {
        require(
            operationsDone[block.number][uint8(Operations.UpdateValidators)] ==
                false,
            "Validators already updated"
        );
        _;
    }
   

    // feeAddr can withdraw profits of it's validator
    function withdrawProfits(address validator) external returns (bool) {
        address payable feeAddr = payable(msg.sender);
        require(
            validatorInfo[validator].status != Status.NotExist,
            "Validator not exist"
        );
        require(
            validatorInfo[validator].feeAddr == feeAddr,
            "You are not the fee receiver of this validator"
        );
        require(
            validatorInfo[validator].lastWithdrawProfitsBlock +
                WithdrawProfitPeriod <=
                block.number,
            "You must wait enough blocks to withdraw your profits after latest withdraw of this validator"
        );
        uint256 hbIncoming = validatorInfo[validator].hbIncoming;
        require(hbIncoming > 0, "You don't have any profits");

        // update info
        validatorInfo[validator].hbIncoming = 0;
        validatorInfo[validator].lastWithdrawProfitsBlock = block.number;

        // send profits to fee address
        if (hbIncoming > 0) {
            feeAddr.transfer(hbIncoming);
        }

        emit LogWithdrawProfits(
            validator,
            feeAddr,
            hbIncoming,
            block.timestamp
        );

        return true;
    }

    function getStakesOfTopValidators(address[] memory rewardSet)
        private
        view
        returns (uint256 total,  uint256[] memory staked)
    {
        staked=new uint256[](rewardSet.length);
        for (uint256 i = 0; i < rewardSet.length; i++) {
               let (,, uint256 coins,,,,) validatorsContract.getValidatorInfo(rewardSet[i]);
                total = total.add(coins);
                staked[i]=coins;
        }

        return (total,  staked);
    }

    function getStakeOfTopValidators(address[] memory rewardSet)
        private
        view
        returns (uint256 total, uint256[] memory staked)
    {
        staked=new uint256[](rewardSet.length);
        for (uint256 i = 0; i < rewardSet.length; i++) {
               (uint256 coins,,) validatorsContract.getStakingInfo(rewardSet[i],rewardSet[i]);
                total = total.add(coins);
                len++;
        }

        return (total,  staked);
    }

    function rewardByYear(uint256 i) external pure returns (uint256) {
        require(i<3,"Only three years");
        uint256[3] memory x = [6250000, 5000000,  3750000];
        return x[i] * ONE;
    }

    // distributeBlockReward distributes block reward to all active validators
    function distributeBlockReward(uint256 beginblock,uint256 endblock, uint256 blocks,address[] memory rewardSet)
        public
    {
        // Jailed validator can't get profits.
        addProfitsToActiveValidatorsByStakePercentExcept(beginblock,endblock,  blocks, rewardSet, address(0));

        emit LogDistributeBlockRewardval, hb, block.timestamp);
    }

//  (
//             v.feeAddr,
//             v.status,
//             v.coins,
//             v.hbIncoming,
//             v.totalJailedHB,
//             v.lastWithdrawProfitsBlock,
//             v.stakers
//         );
    // add profits to all validators by stake percent except the punished validator or jailed validator
    function addProfitsToActiveValidatorsByStakePercentExcept(
       uint256 beginblocks,uint256 endblock, uint256 blocks,address[] memory rewardSet,
        address punishedVal
    ) private {
        uint256 totalRewardStake;
        uint256 rewardValsLen;
        (
            totalRewardStake,
            rewardValsLen
        ) = validatorsContract.getTotalStakeOfActiveValidatorsExcept(punishedVal);
        (uint256 totalTs,uint256 Ts)=getStakesOfTopValidators(rewardSet);
        (uint256 totalTvs,uint256 Tvs)=getStakesOfTopValidators(rewardSet);
        uint256 totalTds=totalTs-totalTvs;
        // SRD1=totalSRD *(1-20)%*50%/Y*(TV +x%*TD)/(TV +TD)+totalSRD *80%*50%* (TV + x% * TD))/ total TV^


        if (rewardValsLen == 0) {
            return;
        }

        uint256 remain;
        address last;

        // no stake(at genesis period)
        if (totalRewardStake == 0) {
            uint256 per = totalReward.div(rewardValsLen);
            remain = totalReward.sub(per.mul(rewardValsLen));

            for (uint256 i = 0; i < currentValidatorSet.length; i++) {
                address val = currentValidatorSet[i];
                if (
                    validatorInfo[val].status != Status.Jailed &&
                    val != punishedVal
                ) {
                    validatorInfo[val].hbIncoming = validatorInfo[val]
                        .hbIncoming
                        .add(per);

                    last = val;
                }
            }

            if (remain > 0 && last != address(0)) {
                validatorInfo[last].hbIncoming = validatorInfo[last]
                    .hbIncoming
                    .add(remain);
            }
            return;
        }

        uint256 added;
        for (uint256 i = 0; i < currentValidatorSet.length; i++) {
            address val = currentValidatorSet[i];
            if (
                validatorInfo[val].status != Status.Jailed && val != punishedVal
            ) {
                uint256 reward = totalReward.mul(validatorInfo[val].coins).div(
                    totalRewardStake
                );
                added = added.add(reward);
                last = val;
                validatorInfo[val].hbIncoming = validatorInfo[val]
                    .hbIncoming
                    .add(reward);
            }
        }

        remain = totalReward.sub(added);
        if (remain > 0 && last != address(0)) {
            validatorInfo[last].hbIncoming = validatorInfo[last].hbIncoming.add(
                remain
            );
        }
    }

}
