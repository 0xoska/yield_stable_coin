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

interface IMessageTransmitterV2 {
    // ============ External Functions  ============
    /**
     * @notice Send the message to the destination domain and recipient
     * @dev Formats the message, and emits a `MessageSent` event with message information.
     * @param destinationDomain Domain of destination chain
     * @param recipient Address of message recipient on destination chain as bytes32
     * @param destinationCaller Caller on the destination domain, as bytes32
     * @param minFinalityThreshold The minimum finality at which the message should be attested to
     * @param messageBody Contents of the message (bytes)
     */
    function sendMessage(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata messageBody
    ) external;

    /**
     * @notice Receive a message. Messages can only be broadcast once for a given nonce.
     * The message body of a valid message is passed to the specified recipient for further processing.
     *
     * @dev Attestation format:
     * A valid attestation is the concatenated 65-byte signature(s) of exactly
     * `thresholdSignature` signatures, in increasing order of attester address.
     * ***If the attester addresses recovered from signatures are not in
     * increasing order, signature verification will fail.***
     * If incorrect number of signatures or duplicate signatures are supplied,
     * signature verification will fail.
     *
     * Message Format:
     *
     * Field                        Bytes      Type       Index
     * version                      4          uint32     0
     * sourceDomain                 4          uint32     4
     * destinationDomain            4          uint32     8
     * nonce                        32         bytes32    12
     * sender                       32         bytes32    44
     * recipient                    32         bytes32    76
     * destinationCaller            32         bytes32    108
     * minFinalityThreshold         4          uint32     140
     * finalityThresholdExecuted    4          uint32     144
     * messageBody                  dynamic    bytes      148
     * @param message Message bytes
     * @param attestation Concatenated 65-byte signature(s) of `message`, in increasing order
     * of the attester address recovered from signatures.
     * @return success True, if successful; false, if not
     */
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}