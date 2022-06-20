pragma solidity >=0.6.0 <0.8.0;

interface IValidators {
    function getActiveValidators() public view returns (address[] memory);

    function getTotalStakeOfActiveValidators()
        public
        view
        returns (uint256 total, uint256 len);

    function getTopValidators() public view returns (address[] memory);

    function getValidatorInfo(address val)
        public
        view
        returns (
            address payable,
            Status,
            uint256,
            uint256,
            uint256,
            uint256,
            address[] memory
        );

    function getStakingInfo(address staker, address val)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
