// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/v4-periphery/src/V4Router.sol";

/** 
    1、 什麼是重入攻擊? 如何預防?
    重入攻擊（Reentrancy Attack）：重入攻擊發生在一個外部呼叫（External Call）在完成前，回調到原合約，造成惡意使用者重複提款或其他非預期的行為。
    預防方法：在執行任何操作之前，先檢查所有前提條件。更新合約的內部狀態變數必須在任何外部呼叫之前完成。

    2、 三種 send Ether 的方式具體差異為何?
    transfer()：如果發送失敗會自動還原（revert）整個交易。
    send()：如果發送失敗，不會自動還原交易，而是返回 false，所以需要自行檢查返回值來處理發送失敗的情況。
    call()：如果呼叫失敗，不會自動還原交易，只會將 success 設定為 false，因此必須自行檢查 success 的返回值。
*/ 

// 3、 實作 Uniswap 交易 ETH / USDC（測試網版本）
contract Transaction {

    IERC20 public USDC;

    // Sepolia addresses
    address public constant UNISWAP_POOLMANAGER_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address public constant USDC_ADDRESS_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address public USDC_ADDRESS;
    
    // Contract owner
    address public owner;

    // Events
    event ContractDeployed (address owner, address USDC_ADDRESS);
    
    constructor() {
        owner = msg.sender;
        
        USDC_ADDRESS = USDC_ADDRESS_SEPOLIA;
        USDC = IERC20(USDC_ADDRESS);
        
        emit ContractDeployed(owner, USDC_ADDRESS);
    }

    modifier onlyOwner() {
        require (msg.sender == owner, "Only owner can do this.");
        _;
    }

    function executeSwap (uint16 balanceOfETH) public view onlyOwner returns (uint16 gainOfUSDC, uint256) {
        // require (USDC.balanceOf(address(this)) >= balanceOfETH, "Insufficient ETH.");

        gainOfUSDC = balanceOfETH * 3039;

        return (gainOfUSDC, USDC.balanceOf(address(this)));
    }
}