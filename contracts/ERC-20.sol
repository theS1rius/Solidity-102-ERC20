// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

/** 
    1、 什麼是重入攻擊? 如何預防?
    重入攻擊（Reentrancy Attack）：重入攻擊發生在一個外部呼叫（External Call）在完成前，回調到原合約，造成惡意使用者重複提款或其他非預期的行為。
    預防方法：在執行任何操作之前，先檢查所有前提條件。更新合約的內部狀態變數必須在任何外部呼叫之前完成。

    2、 三種 send Ether 的方式具體差異為何?
    transfer()：如果發送失敗會自動還原（revert）整個交易。
    send()：如果發送失敗，不會自動還原交易，而是返回 false，所以需要自行檢查返回值來處理發送失敗的情況。
    call()：如果呼叫失敗，不會自動還原交易，只會將 success 設定為 false，因此必須自行檢查 success 的返回值。
*/ 

// 3、 實作
contract ERC20 { 

}