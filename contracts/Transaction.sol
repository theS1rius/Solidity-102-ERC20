// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

// Uniswap V2 Router
interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(
        uint amountIn, 
        address[] calldata path
    ) external view returns (uint[] memory amounts);
    
    function WETH() external pure returns (address);
}

/** 
    1、 什麼是重入攻擊? 如何預防?
    重入攻擊（Reentrancy Attack）：重入攻擊發生在一個外部呼叫（External Call）在完成前，回調到原合約，造成惡意使用者重複提款或其他非預期的行為。
    預防方法：在執行任何操作之前，先檢查所有前提條件。更新合約的內部狀態變數必須在任何外部呼叫之前完成。

    2、 三種 send Ether 的方式具體差異為何?
    transfer()：如果發送失敗會自動還原（revert）整個交易。
    send()：如果發送失敗，不會自動還原交易，而是返回 false，所以需要自行檢查返回值來處理發送失敗的情況。
    call()：如果呼叫失敗，不會自動還原交易，只會將 success 設定為 false，因此必須自行檢查 success 的返回值。
*/ 

// 3、 實作 Uniswap 交易 ETH / USDT
contract Transaction {
    // Uniswap V2 Router address (mainnet)
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // USDT contract address (mainnet)
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Sepolia testnet Uniswap V2 Router address
    address public constant UNISWAP_ROUTER_Sepolia = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    // Sepolia testnet USDT contract address
    address public constant USDT_ADDRESS_Sepolia = 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06;
  
    // contract owner
    address public owner;
    
    // Uniswap Router instance
    IUniswapV2Router public uniswapRouter;
    
    // USDT token instance
    IERC20 public usdtToken;
    
    // declare event
    event EthToUsdtSwap(address user, uint256 ethAmount, uint256 usdtAmount);
    event UsdtToEthSwap(address user, uint256 usdtAmount, uint256 ethAmount);
    event PriceChecked(uint256 ethAmount, uint256 expectedUsdt);
    
    constructor() {
        owner = msg.sender;
        uniswapRouter = IUniswapV2Router(UNISWAP_ROUTER_Sepolia);
        usdtToken = IERC20(USDT_ADDRESS_Sepolia);
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can execute.");
        _;
    }
    
    // ETH to USDT
    function swapEthToUsdt(uint256 minUsdtAmount) external payable {
        require(msg.value > 0, "ETH must be greater than zero.");
        
        // ETH -> WETH -> USDT
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = USDT_ADDRESS_Sepolia;
        
        // 設定交易截止時間（當前時間 + 10分鐘）
        uint256 deadline = block.timestamp + 600;
        
        // execute transaction
        uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: msg.value}(
            minUsdtAmount,
            path,
            msg.sender,
            deadline
        );
        
        emit EthToUsdtSwap(msg.sender, msg.value, amounts[1]);
    }
    
    // USDT to ETH
    function swapUsdtToEth(uint256 usdtAmount, uint256 minEthAmount) external {
        require(usdtAmount > 0, "USDT must be greater than zero.");
        
        // 檢查用戶USDT餘額
        require(usdtToken.balanceOf(msg.sender) >= usdtAmount, "USDT are not enough.");
        
        // 用戶需要先授權合約使用其USDT
        require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "USDT transaction failed.");
        
        // 授權Uniswap Router使用USDT
        usdtToken.approve(UNISWAP_ROUTER_Sepolia, usdtAmount);
        
        // 設定交易路徑：USDT -> WETH -> ETH
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS_Sepolia;
        path[1] = uniswapRouter.WETH();
        
        // 設定交易截止時間
        uint256 deadline = block.timestamp + 600;
        
        // 執行交易
        uint[] memory amounts = uniswapRouter.swapExactTokensForETH(
            usdtAmount,
            minEthAmount,
            path,
            msg.sender,
            deadline
        );
        
        emit UsdtToEthSwap(msg.sender, usdtAmount, amounts[1]);
    }
    
    // 查詢價格 - ETH 換 USDT
    function getEthToUsdtPrice(uint256 ethAmount) external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = USDT_ADDRESS_Sepolia;
        
        uint[] memory amounts = uniswapRouter.getAmountsOut(ethAmount, path);
        return amounts[1];
    }
    
    // 查詢價格 - USDT 換 ETH
    function getUsdtToEthPrice(uint256 usdtAmount) external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS_Sepolia;
        path[1] = uniswapRouter.WETH();
        
        uint[] memory amounts = uniswapRouter.getAmountsOut(usdtAmount, path);
        return amounts[1];
    }
    
    // 檢查合約ETH餘額
    function getContractEthBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // 檢查合約USDT餘額
    function getContractUsdtBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }
    
    // 檢查用戶USDT餘額
    function getUserUsdtBalance(address user) external view returns (uint256) {
        return usdtToken.balanceOf(user);
    }
    
    // 接收ETH的函數
    receive() external payable {
        // 允許合約接收ETH
    }
}