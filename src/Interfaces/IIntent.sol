// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIntent {
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    struct InitData {
        bytes32 intentId;
        address owner;
        address receiver;
        address tokenOut;
        uint256 amountOutMin;
        uint256 deadline;
    }
}
