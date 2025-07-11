// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uniswap V2 Router Interface
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
        address[] memory path
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

// 3、 實作 Uniswap 交易 ETH / USDT（測試網版本）
contract Transaction {
    // Mainnet address
    address public constant UNISWAP_ROUTER_MAINNET = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant USDT_ADDRESS_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Sepolia address
    address public constant UNISWAP_ROUTER_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address public constant USDT_ADDRESS_SEPOLIA = 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06;
    
    // Current address
    address public immutable UNISWAP_ROUTER;
    address public immutable USDT_ADDRESS;
    
    // Contract owner
    address public owner;
    
    // Uniswap Router instance
    IUniswapV2Router public uniswapRouter;
    
    // USDT token instance
    IERC20 public usdtToken;
    
    // Prevent Re-Entrancy
    bool private locked;
    
    // declare event
    event EthToUsdtSwap(address indexed user, uint256 ethAmount, uint256 usdtAmount);
    event UsdtToEthSwap(address indexed user, uint256 usdtAmount, uint256 ethAmount);
    event PriceChecked(uint256 ethAmount, uint256 expectedUsdt);
    event ContractDeployed(address indexed owner, address router, address token);
    
    // Choose network：false = Sepolia, true = mainnet
    constructor(bool useMainnet) {
        owner = msg.sender;
        locked = false;
        
        if (useMainnet) {
            UNISWAP_ROUTER = UNISWAP_ROUTER_MAINNET;
            USDT_ADDRESS = USDT_ADDRESS_MAINNET;
        } else {
            UNISWAP_ROUTER = UNISWAP_ROUTER_SEPOLIA;
            USDT_ADDRESS = USDT_ADDRESS_SEPOLIA;
        }
        
        uniswapRouter = IUniswapV2Router(UNISWAP_ROUTER);
        usdtToken = IERC20(USDT_ADDRESS);
        
        emit ContractDeployed(owner, UNISWAP_ROUTER, USDT_ADDRESS);
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can execute.");
        _;
    }
    
    // Prevent Re-Entrancy
    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard: reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    // ETH to USDT
    function swapEthToUsdt(uint256 minUsdtAmount) external payable nonReentrant {
        require(msg.value > 0, "ETH must be greater than zero.");
        require(minUsdtAmount > 0, "Minimum USDT amount must be greater than zero.");
        
        // 設定交易路徑：ETH -> WETH -> USDT
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = USDT_ADDRESS;
        
        // 設定交易截止時間（當前時間 + 20分鐘）
        uint256 deadline = block.timestamp + 1200;
        
        // 執行交易
        uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: msg.value}(
            minUsdtAmount,
            path,
            msg.sender,
            deadline
        );
        
        emit EthToUsdtSwap(msg.sender, msg.value, amounts[1]);
    }
    
    // USDT to ETH
    function swapUsdtToEth(uint256 usdtAmount, uint256 minEthAmount) external nonReentrant {
        require(usdtAmount > 0, "USDT must be greater than zero.");
        require(minEthAmount > 0, "Minimum ETH amount must be greater than zero.");
        
        // 檢查用戶USDT餘額
        require(usdtToken.balanceOf(msg.sender) >= usdtAmount, "USDT are not enough.");
        
        // 用戶需要先授權合約使用其USDT
        require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "USDT transaction failed.");
        
        // 授權Uniswap Router使用USDT
        require(usdtToken.approve(UNISWAP_ROUTER, usdtAmount), "USDT approve failed.");
        
        // 設定交易路徑：USDT -> WETH -> ETH
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS;
        path[1] = uniswapRouter.WETH();
        
        // 設定交易截止時間
        uint256 deadline = block.timestamp + 1200;
        
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
        require(ethAmount > 0, "ETH amount must be greater than zero.");
        
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = USDT_ADDRESS;
        
        uint[] memory amounts = uniswapRouter.getAmountsOut(ethAmount, path);
        return amounts[1];
    }
    
    // 查詢價格 - USDT 換 ETH
    function getUsdtToEthPrice(uint256 usdtAmount) external view returns (uint256) {
        require(usdtAmount > 0, "USDT amount must be greater than zero.");
        
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS;
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
        require(user != address(0), "Invalid user address.");
        return usdtToken.balanceOf(user);
    }
    
    // 檢查用戶ETH餘額
    function getUserEthBalance(address user) external view returns (uint256) {
        require(user != address(0), "Invalid user address.");
        return user.balance;
    }
    
    // 獲取USDT代幣信息
    function getUsdtDecimals() external view returns (uint256) {
        return usdtToken.totalSupply();
    }
    
    // 獲取WETH地址
    function getWethAddress() external view returns (address) {
        return uniswapRouter.WETH();
    }
    
    // 獲取當前使用的路由器和代幣地址
    function getAddresses() external view returns (address routerAddr, address tokenAddr) {
        return (UNISWAP_ROUTER, USDT_ADDRESS);
    }
    
    // receive ETH function
    receive() external payable {}
    
    // fallback function
    fallback() external payable {}
}