pragma solidity >=0.6.0 <0.8.0;



import "../Params.sol";
import "../interfaces/IVotePool.sol";
import "../interfaces/IValidators.sol";

contract MockPunish is Params {
    // clean validator's punish record if one restake in
    function cleanPunishRecord(address)
    external
    onlyInitialized
    returns (bool)
    {
        return true;
    }
}
