// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { LibClone } from "solady/utils/LibClone.sol";
import { IIntent } from "../Interfaces/IIntent.sol";
import { SwapIntentHandler } from "../Helpers/SwapIntentHandler.sol";
import { TransferrableOwnership } from "../Helpers/TransferrableOwnership.sol";

/// @title Intent Factory
/// @author LI.FI (https://li.fi)
/// @notice Deploys minimal proxies of "intents" that can execute arbitrary calls.
/// @custom:version 1.0.0
contract IntentFactory is TransferrableOwnership {
    /// Storage ///

    address public immutable implementation;

    /// Errors ///

    error Unauthorized();

    /// Constructor ///

    constructor(address _owner) TransferrableOwnership(_owner) {
        implementation = payable(address(new SwapIntentHandler()));
    }

    /// External Functions ///

    /// @notice Deploys a new intent and executes the given calls.
    /// @param _initData The init data.
    /// @param _calls The calls to execute.
    function deployAndExecuteIntent(
        IIntent.InitData calldata _initData,
        IIntent.Call[] calldata _calls
    ) external {
        if (msg.sender != owner) {
            revert Unauthorized();
        }

        bytes32 salt = keccak256(abi.encode(_initData));
        address payable clone = payable(
            LibClone.cloneDeterministic(implementation, salt)
        );
        SwapIntentHandler(clone).init(_initData);
        SwapIntentHandler(clone).execute(_calls);
    }

    /// @notice Deploys a new intent and withdraws all the tokens.
    /// @param _initData The init data.
    /// @param tokens The tokens to withdraw.
    function deployAndWithdrawAll(
        IIntent.InitData calldata _initData,
        address[] calldata tokens,
        address payable receiver
    ) external {
        if (msg.sender != _initData.owner) {
            revert Unauthorized();
        }
        bytes32 salt = keccak256(abi.encode(_initData));
        address payable clone = payable(
            LibClone.cloneDeterministic(implementation, salt)
        );
        SwapIntentHandler(clone).init(_initData);
        SwapIntentHandler(clone).withdrawAll(tokens, receiver);
    }

    /// @notice Predicts the address of the intent.
    /// @param _initData The init data.
    function getIntentAddress(
        IIntent.InitData calldata _initData
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(_initData));
        return
            LibClone.predictDeterministicAddress(
                implementation,
                salt,
                address(this)
            );
    }
}
