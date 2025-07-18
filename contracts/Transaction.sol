/** 
    1、 什麼是重入攻擊? 如何預防?
    重入攻擊（Reentrancy Attack）：重入攻擊發生在一個外部呼叫（External Call）在完成前，回調到原合約，造成惡意使用者重複提款或其他非預期的行為。
    預防方法：在執行任何操作之前，先檢查所有前提條件。更新合約的內部狀態變數必須在任何外部呼叫之前完成。

    2、 三種 send Ether 的方式具體差異為何?
    transfer()：如果發送失敗會自動還原（revert）整個交易。
    send()：如果發送失敗，不會自動還原交易，而是返回 false，所以需要自行檢查返回值來處理發送失敗的情況。
    call()：如果呼叫失敗，不會自動還原交易，只會將 success 設定為 false，因此必須自行檢查 success 的返回值。

    3、 實作 Uniswap 交易 ETH / USDC（測試網版本）
    
*/ 

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Transaction is ReentrancyGuard, IUnlockCallback {
    IPoolManager public poolManager;

    // Sepolia addresses
    address public constant POOLMANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address public constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address public constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address public USDC_ADDRESS;
    
    // Contract owner
    address public owner;

    struct SwapCallbackData {
        address recipient;
        uint256 amountIn;
        uint256 minAmountOut;
        bool ethToUsdc;
    }

    // Events
    event ContractDeployed (address owner, address USDC_ADDRESS);
    event SwapExecuted(address indexed user, uint256 ethAmount, uint256 usdcAmount);
    event Log (string log);
    
    constructor (address _poolManager) payable {
        owner = msg.sender;
        poolManager = IPoolManager(_poolManager);
        
        emit ContractDeployed(owner, USDC);
    }

    modifier onlyOwner() {
        require (msg.sender == owner, "Only owner can do this.");
        _;
    }

    function executeSwap (
        uint256 balanceOfETH
        ) public onlyOwner nonReentrant payable returns (
            uint256 ethAmount,
            uint256 usdcAmount
        ) {
        require (getUserBalance() >= balanceOfETH, "Insufficient ETH.");

        require(msg.value > 0, "Must send ETH");
        
        ethAmount = msg.value;
        
        IWETH(WETH).deposit{value: ethAmount}();
        
        require(
            IWETH(WETH).approve(address(poolManager), ethAmount),
            "WETH approve failed"
        );

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(this));
        uint256 minUSDCOut;
        
        SwapCallbackData memory callbackData = SwapCallbackData({
            recipient: msg.sender,
            amountIn: ethAmount,
            minAmountOut: minUSDCOut,
            ethToUsdc: true
        });
        
        poolManager.unlock(abi.encode(callbackData));
        
        usdcAmount = IERC20(USDC).balanceOf(address(this)) - usdcBefore;
        require(usdcAmount >= minUSDCOut, "Insufficient USDC output");
        
        require(
            IERC20(USDC).transfer(msg.sender, usdcAmount),
            "USDC transfer failed"
        );
        
        emit SwapExecuted(msg.sender, ethAmount, usdcAmount);
        
        return (ethAmount, usdcAmount);
    }

    // get user ETH balance
    function getUserBalance() public view returns (uint256) {
        return msg.sender.balance;
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only pool manager");
        
        SwapCallbackData memory callbackData = abi.decode(data, (SwapCallbackData));
        
        PoolKey memory key = _getPoolKey();
        
        SwapParams memory params = SwapParams({
            zeroForOne: _isZeroForOne(callbackData.ethToUsdc),
            amountSpecified: int256(callbackData.amountIn),
            sqrtPriceLimitX96: callbackData.ethToUsdc 
                ? TickMath.MIN_SQRT_PRICE + 1 
                : TickMath.MAX_SQRT_PRICE - 1
        });
        
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        _settleDelta(key.currency0, delta.amount0());
        _settleDelta(key.currency1, delta.amount1());
        
        emit Log("Swap executed in unlock callback");
        
        return "";
    }

    function _getPoolKey() internal pure returns (PoolKey memory) {

        (Currency currency0, Currency currency1) = WETH < USDC 
            ? (Currency.wrap(WETH), Currency.wrap(USDC))
            : (Currency.wrap(USDC), Currency.wrap(WETH));
            
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _isZeroForOne(bool ethToUsdc) internal pure returns (bool) {
        if (WETH < USDC) {
            return ethToUsdc; // WETH -> USDC
        } else {
            return !ethToUsdc; // USDC -> WETH
        }
    }

    function _settleDelta(Currency currency, int128 deltaAmount) internal {
        if (deltaAmount > 0) {

            address token = Currency.unwrap(currency);
            IERC20(token).transfer(address(poolManager), uint128(deltaAmount));
            poolManager.settle();
        } else if (deltaAmount < 0) {

            poolManager.take(currency, address(this), uint128(-deltaAmount));
        }
    }

    // for testing
    function swapETHToUSDC (
        // uint256 minOut
        ) public payable {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(USDC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        uint256 balanceBefore = IERC20(USDC).balanceOf(address(this));

        poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: int256(msg.value),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        uint256 balanceAfter = IERC20(USDC).balanceOf(address(this));
        uint256 actualOutput = balanceAfter - balanceBefore;

        // require(actualOutput >= minOut, "Insufficient output.");

        (bool result, ) = (msg.sender).call{value: actualOutput}("");
        require(result, "Call failed.");
    }

    receive() external payable {}
}