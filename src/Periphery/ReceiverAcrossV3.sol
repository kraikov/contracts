// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";
import { LibAsset } from "../Libraries/LibAsset.sol";
import { LibUtil } from "../Libraries/LibUtil.sol";
import { ILiFi } from "../Interfaces/ILiFi.sol";
import { IExecutor } from "../Interfaces/IExecutor.sol";
import { TransferrableOwnership } from "../Helpers/TransferrableOwnership.sol";
import { ExternalCallFailed, UnAuthorized } from "../Errors/GenericErrors.sol";

/// @title ReceiverAcrossV3
/// @author LI.FI (https://li.fi)
/// @notice Arbitrary execution contract used for cross-chain swaps and message passing via AcrossV3
/// @custom:version 1.0.0
contract ReceiverAcrossV3 is ILiFi, TransferrableOwnership {
    using SafeERC20 for IERC20;

    /// Error ///
    error InsufficientGasLimit(uint256 gasLeft);

    /// Storage ///
    IExecutor public immutable executor;
    address public immutable spokepool;
    uint256 public immutable recoverGas;

    /// Modifiers ///
    modifier onlySpokepool() {
        if (msg.sender != spokepool) {
            revert UnAuthorized();
        }
        _;
    }

    /// Constructor
    constructor(
        address _owner,
        address _executor,
        address _spokepool,
        uint256 _recoverGas
    ) TransferrableOwnership(_owner) {
        owner = _owner;
        executor = IExecutor(_executor);
        spokepool = _spokepool;
        recoverGas = _recoverGas;
    }

    /// External Methods ///

    /// @notice Completes an AcrossV3 cross-chain transaction on the receiving chain
    /// @dev Token transfer and message execution will happen in one atomic transaction
    /// @dev This function can only be called the Across SpokePool on this network
    /// @param tokenSent The address of the token that was received
    /// @param amount The amount of tokens received
    /// @param * - unused(relayer) The address of the relayer who is executing this message
    /// @param message The composed message payload in bytes
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address,
        bytes memory message
    ) external payable onlySpokepool {
        // decode payload
        (
            bytes32 transactionId,
            LibSwap.SwapData[] memory swapData,
            address receiver
        ) = abi.decode(message, (bytes32, LibSwap.SwapData[], address));

        // execute swap(s)
        _swapAndCompleteBridgeTokens(
            transactionId,
            swapData,
            tokenSent,
            payable(receiver),
            amount
        );
    }

    /// @notice Send remaining token to receiver
    /// @param assetId address of the token to be withdrawn (not to be confused with StargateV2's assetIds which are uint16 values)
    /// @param receiver address that will receive tokens in the end
    /// @param amount amount of token
    function pullToken(
        address assetId,
        address payable receiver,
        uint256 amount
    ) external onlyOwner {
        if (LibAsset.isNativeAsset(assetId)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = receiver.call{ value: amount }("");
            if (!success) revert ExternalCallFailed();
        } else {
            IERC20(assetId).safeTransfer(receiver, amount);
        }
    }

    /// Private Methods ///

    /// @notice Performs a swap before completing a cross-chain transaction
    /// @param _transactionId the transaction id associated with the operation
    /// @param _swapData array of data needed for swaps
    /// @param assetId address of the token received from the source chain (not to be confused with StargateV2's assetIds which are uint16 values)
    /// @param receiver address that will receive tokens in the end
    /// @param amount amount of token
    function _swapAndCompleteBridgeTokens(
        bytes32 _transactionId,
        LibSwap.SwapData[] memory _swapData,
        address assetId,
        address payable receiver,
        uint256 amount
    ) private {
        if (LibAsset.isNativeAsset(assetId)) {
            // case 1: native asset
            uint256 cacheGasLeft = gasleft();
            if (cacheGasLeft < recoverGas) {
                // case 1a: not enough gas left to execute calls
                // @dev: we removed the handling to send bridged funds to receiver in case of insufficient gas
                //       as it's better for AcrossV3 to revert these cases instead
                revert InsufficientGasLimit(cacheGasLeft);
            }

            // case 1b: enough gas left to execute calls
            // solhint-disable no-empty-blocks
            try
                executor.swapAndCompleteBridgeTokens{
                    value: amount,
                    gas: cacheGasLeft - recoverGas
                }(_transactionId, _swapData, assetId, receiver)
            {} catch {
                cacheGasLeft = gasleft();
                // if the only gas left here is the recoverGas then the swap must have failed due to out-of-gas error and in this case we want to revert
                if (cacheGasLeft <= recoverGas)
                    revert InsufficientGasLimit(cacheGasLeft);

                // send the bridged (and unswapped) funds to receiver address
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = receiver.call{ value: amount }("");
                if (!success) revert ExternalCallFailed();

                emit LiFiTransferRecovered(
                    _transactionId,
                    assetId,
                    receiver,
                    amount,
                    block.timestamp
                );
            }
        } else {
            // case 2: ERC20 asset
            uint256 cacheGasLeft = gasleft();
            IERC20 token = IERC20(assetId);
            token.safeApprove(address(executor), 0);

            if (cacheGasLeft < recoverGas) {
                // case 2a: not enough gas left to execute calls
                // @dev: we removed the handling to send bridged funds to receiver in case of insufficient gas
                //       as it's better for AcrossV3 to revert these cases instead
                revert InsufficientGasLimit(cacheGasLeft);
            }

            // case 2b: enough gas left to execute calls
            token.safeIncreaseAllowance(address(executor), amount);
            try
                executor.swapAndCompleteBridgeTokens{
                    gas: cacheGasLeft - recoverGas
                }(_transactionId, _swapData, assetId, receiver)
            {} catch {
                cacheGasLeft = gasleft();
                // if the only gas left here is the recoverGas then the swap must have failed due to out-of-gas error and in this case we want to revert
                if (cacheGasLeft <= recoverGas)
                    revert InsufficientGasLimit(cacheGasLeft);

                // send the bridged (and unswapped) funds to receiver address
                token.safeTransfer(receiver, amount);

                emit LiFiTransferRecovered(
                    _transactionId,
                    assetId,
                    receiver,
                    amount,
                    block.timestamp
                );
            }

            // reset approval to 0
            token.safeApprove(address(executor), 0);
        }
    }

    /// @notice Receive native asset directly.
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
