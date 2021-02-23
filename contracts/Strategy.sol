// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public immutable dev = 0x5cAf454Ba92e6F2c929DF14667Ee360eD9fD5b26;
    address
        public immutable addressConfig = 0x1D415aa39D647834786EB9B5a333A50e9935b796;
    address public immutable property;
    string public override name;

    constructor(
        address _vault,
        address _property,
        string memory _name
    ) public BaseStrategy(_vault) {
        property = _property;
        name = _name;

        debtThreshold = 100 * 1e18;
        //we do this horrible thing because you can't compare strings in solidity
        require(
            keccak256(bytes(apiVersion())) ==
                keccak256(bytes(VaultAPI(_vault).apiVersion())),
            "WRONG VERSION"
        );
    }

    constructor(address _vault) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external override view returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategyVyperFunDEV";
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant().add(balanceOfStake()).add(devFutureProfit());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Try to pay debt asap
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = liquidatePosition(_debtOutstanding);
            // Using Math.min() since we might free more than needed
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        // Harvest profits
        if (devFutureProfit() > 0) {
            uint256 balanceBeforeProfit = balanceOfWant();
            // Withdraw with 0 amount will give us the reward.
            lockup().withdraw(property, 0);
            _profit = balanceOfWant().sub(balanceBeforeProfit);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            IDev(dev).deposit(property, _wantAvailable);
        }
    }

    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        return prepareReturn(_debtOutstanding);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _amountFreed)
    {
        if (balanceOfWant() < _amountNeeded) {
            // Let's withdraw all and deposit back what we don't need
            lockup().withdraw(
                property,
                lockup().getValue(property, address(this))
            );

            // We might be able to deposit back the remaining
            uint256 _wantAvailable = balanceOfWant().sub(_amountNeeded);
            if (_wantAvailable > 0) {
                IDev(dev).deposit(property, _wantAvailable);
            }
        }

        _amountFreed = balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        lockup().withdraw(property, lockup().getValue(property, address(this)));
        IERC20(want).transfer(_newStrategy, balanceOfWant());
    }

    function protectedTokens()
        internal
        override
        view
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = address(want);
        return protected;
    }

    function lockup() public view returns (ILockup) {
        return ILockup(IAddressConfig(addressConfig).lockup());
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return lockup().getValue(property, address(this));
    }

    function devFutureProfit() public view returns (uint256) {
        return
            lockup().calculateWithdrawableInterestAmount(
                property,
                address(this)
            );
    }
}
