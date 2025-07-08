/*
 * Copyright 2024 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity >=0.7.6;

interface ITokenMessengerV2{

    event DepositForBurn(
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 indexed minFinalityThreshold,
        bytes hookData
    );

// ============ External Functions  ============
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - given burnToken is not supported
     * - given destinationDomain has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - maxFee is greater than or equal to `amount`.
     * - MessageTransmitterV2#sendMessage reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain to receive message on
     * @param mintRecipient address of mint recipient on destination domain
     * @param burnToken token to burn `amount` of, on local domain
     * @param destinationCaller authorized caller on the destination domain, as bytes32. If equal to bytes32(0),
     * any address can broadcast the message.
     * @param maxFee maximum fee to pay on the destination domain, specified in units of burnToken
     * @param minFinalityThreshold the minimum finality at which a burn message will be attested to.
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external;

    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - `hookData` is zero-length
     * - `burnToken` is not supported
     * - `destinationDomain` has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - maxFee is greater than or equal to `amount`.
     * - MessageTransmitterV2#sendMessage reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain to receive message on
     * @param mintRecipient address of mint recipient on destination domain, as bytes32
     * @param burnToken token to burn `amount` of, on local domain
     * @param destinationCaller authorized caller on the destination domain, as bytes32. If equal to bytes32(0),
     * any address can broadcast the message.
     * @param maxFee maximum fee to pay on the destination domain, specified in units of burnToken
     * @param hookData hook data to append to burn message for interpretation on destination domain
     */
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external;

    /**
     * @notice Handles an incoming finalized message received by the local MessageTransmitter,
     * and takes the appropriate action. For a burn message, mints the
     * associated token to the requested recipient on the local domain.
     * @dev Validates the local sender is the local MessageTransmitter, and the
     * remote sender is a registered remote TokenMessenger for `remoteDomain`.
     * @param remoteDomain The domain where the message originated from.
     * @param sender The sender of the message (remote TokenMessenger).
     * @param messageBody The message body bytes.
     * @return success Bool, true if successful.
     */
    function handleReceiveFinalizedMessage(
        uint32 remoteDomain,
        bytes32 sender,
        uint32,
        bytes calldata messageBody
    )
        external
        returns (bool);

    /**
     * @notice Handles an incoming unfinalized message received by the local MessageTransmitter,
     * and takes the appropriate action. For a burn message, mints the
     * associated token to the requested recipient on the local domain, less fees.
     * Fees are separately minted to the currently set `feeRecipient` address.
     * @dev Validates the local sender is the local MessageTransmitter, and the
     * remote sender is a registered remote TokenMessenger for `remoteDomain`.
     * @dev Validates that `finalityThresholdExecuted` is at least 500.
     * @param remoteDomain The domain where the message originated from.
     * @param sender The sender of the message (remote TokenMessenger).
     * @param finalityThresholdExecuted The level of finality at which the message was attested to
     * @param messageBody The message body bytes.
     * @return success Bool, true if successful.
     */
    function handleReceiveUnfinalizedMessage(
        uint32 remoteDomain,
        bytes32 sender,
        uint32 finalityThresholdExecuted,
        bytes calldata messageBody
    )
        external
        returns (bool);
}