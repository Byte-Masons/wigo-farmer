// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv2.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev Deposit LP in masterChef. Harvest WIGO rewards and recompound.
 */
contract ReaperStrategyWigo is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant WIGO_ROUTER = address(0x5023882f4D1EC10544FCB2066abE9C1645E95AA0);
    address public constant masterChef = address(0xA1a938855735C0651A6CfE2E93a32A28A236d0E9);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {WIGO} - Reward token for depositing LP into masterChef.
     * {want} - Address of the LP token to farm. (lowercase name for FE compatibility)
     * {lpToken0} (name for FE compatibility)
     * {lpToken1} (name for FE compatibility)
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant WIGO = address(0xE992bEAb6659BFF447893641A378FbbF031C5bD6);
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Wigo variables
     * {poolId} - ID of pool in which to deposit LP tokens
     */
    uint256 public poolId;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _want,
        uint256 _poolId
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        want = _want;
        poolId = _poolId;
        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeIncreaseAllowance(masterChef, wantBalance);
            IMasterChef(masterChef).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMasterChef(masterChef).withdraw(poolId, _amount - wantBal);
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {WIGO} from the {masterChef}.
     *      2. Swaps {WIGO} to {WFTM} using {WIGO_ROUTER}.
     *      3. Claims fees for the harvest caller and treasury.
     *      4. Swaps WFTM to LP want token
     *      5. Deposits {want} into {masterChef} to farm Wigo rewards
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapRewardsToWFTM();
        _chargeFees();
        _addLiquidity();
        deposit();
    }

    function _claimRewards() internal {
        IMasterChef(masterChef).deposit(poolId, 0); // deposit 0 to claim rewards
    }

    function _swapRewardsToWFTM() internal {
        uint256 wigoBalance = IERC20Upgradeable(WIGO).balanceOf(address(this));
        _swap(WIGO, WFTM, wigoBalance);
    }

    /**
     * @dev Helper function to swap tokens given an {_amount}, swap {_path}, and {_router}.
     */
    function _swap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == _to || _amount == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        IERC20Upgradeable(_from).safeIncreaseAllowance(WIGO_ROUTER, _amount);
        IUniswapV2Router02(WIGO_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmBalanceHalf = wftm.balanceOf(address(this)) / 2;

        if (lpToken0 == WFTM) {
            _swap(WFTM, lpToken1, wftmBalanceHalf);
        } else {
            _swap(WFTM, lpToken0, wftmBalanceHalf);
        }

        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        if (lp0Bal != 0 && lp1Bal != 0) {
            IERC20Upgradeable(lpToken0).safeIncreaseAllowance(WIGO_ROUTER, lp0Bal);
            IERC20Upgradeable(lpToken1).safeIncreaseAllowance(WIGO_ROUTER, lp1Bal);
            IUniswapV2Router02(WIGO_ROUTER).addLiquidity(
                lpToken0,
                lpToken1,
                lp0Bal,
                lp1Bal,
                0,
                0,
                address(this),
                block.timestamp
            );
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 amount, ) = IMasterChef(masterChef).userInfo(poolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IMasterChef(masterChef).pendingWigo(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(WIGO).balanceOf(address(this));

        if (totalRewards != 0) {
            address[] memory path = new address[](2);
            path[0] = WIGO;
            path[1] = WFTM;
            profit += IUniswapV2Router02(WIGO_ROUTER).getAmountsOut(totalRewards, path)[1];
        }

        profit += IERC20Upgradeable(WFTM).balanceOf(address(this));

        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        (uint256 poolBal, ) = IMasterChef(masterChef).userInfo(poolId, address(this));
        IMasterChef(masterChef).withdraw(poolId, poolBal);

        uint256 wigoBalance = IERC20Upgradeable(WIGO).balanceOf(address(this));
        _swap(WIGO, WFTM, wigoBalance);
        
        _addLiquidity();

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChef(masterChef).emergencyWithdraw(poolId);
    }
}
