// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Decoder} from "./libraries/Decoder.sol";

import {IMessageTransmitterV2} from "./interfaces/cctpV2/IMessageTransmitterV2.sol";
import {ITokenMessengerV2} from "./interfaces/cctpV2/ITokenMessengerV2.sol";
import {MessageV2} from "./libraries/cctpV2/MessageV2.sol";
import {BurnMessageV2} from "./libraries/cctpV2/BurnMessageV2.sol";
import {TypedMemView} from "./libraries/TypedMemView.sol";

contract AzUsdCCTPV2 {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // The supported Message Format version
    uint32 private constant supportedMessageVersion = 1;
    // The supported Message Body version
    uint32 private constant supportedMessageBodyVersion = 1;
    // Byte-length of an address
    uint256 private constant ADDRESS_BYTE_LENGTH = 20;
    uint256 private constant ZERO = 0;

    bytes32 private BYTES32ZERO;

    address public cctpTokenMessagerV2;
    address public cctpMessageTransmitterV2;

    constructor(address _cctpTokenMessagerV2, address _cctpMessageTransmitterV2) {
        cctpTokenMessagerV2 = _cctpTokenMessagerV2;
        cctpMessageTransmitterV2 = _cctpMessageTransmitterV2;
    }

    /**
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

     * Message Body:
     * Field                        Bytes      Type       Index
     * version                      4          uint32     0
     * burnToken                    4          bytes32     4
     * mintRecipient                4          bytes32     36
     * amount                       32         uint256    68
     * messageSender                32         bytes32    100
     * maxFee                       32         uint256    132
     * feeExecuted                  32         uint256    164
     * expirationBlock              4          uint256     196
     * hookData                     4          uint32     228
     */
    function receiveUSDCAndData(
        bytes calldata message,
        bytes calldata attestation
    ) public {
        uint32 messageVersion = Decoder.getMessageVersion(message);
        uint32 messageBodyVersion = Decoder.getMessageBodyVersion(message);
        bytes memory hookdata = Decoder.decodeMessageToHookdata(message);
        // Validate message version
        require(
            messageVersion == supportedMessageVersion &&
                messageBodyVersion == supportedMessageBodyVersion,
            "Invalid version"
        );

        // Relay message
        require(IMessageTransmitterV2(cctpMessageTransmitterV2).receiveMessage(
            message,
            attestation
        ), "Receive message failed");
        emit TouchReceiveMessgae(hookdata);
        
    }

    function crossMessage(
        address token,
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        uint256 maxFee
    ) external {
        uint256 refundId = 100;
        IMessageTransmitterV2(cctpMessageTransmitterV2).sendMessage(
            destinationDomain, 
            recipient, 
            BYTES32ZERO, 
            minFinalityThreshold, 
            abi.encodePacked(
                supportedMessageBodyVersion, 
                addressToBytes32(token), 
                recipient, 
                ZERO, 
                addressToBytes32(address(this)), 
                maxFee, 
                ZERO,
                ZERO,
                abi.encode(refundId, msg.sender)
            )
        );
    }

    event TouchReceiveMessgae(bytes data);
    function handleReceiveFinalizedMessage(
        uint32 remoteDomain,
        bytes32 sender,
        bytes calldata message,
        bytes calldata attestation
    ) external {
        // Validate message
        bytes29 _msg = message.ref(0);
        MessageV2._validateMessageFormat(_msg);
        require(
            MessageV2._getVersion(_msg) == supportedMessageVersion,
            "Invalid message version"
        );

        // Validate burn message
        bytes29 _msgBody = MessageV2._getMessageBody(_msg);
        BurnMessageV2._validateBurnMessageFormat(_msgBody);
        require(
            BurnMessageV2._getVersion(_msgBody) == supportedMessageBodyVersion,
            "Invalid message body version"
        );

        ITokenMessengerV2(cctpTokenMessagerV2).handleReceiveFinalizedMessage(
            remoteDomain, 
            sender, 
            0, 
            message[148:]
        );
        emit TouchReceiveMessgae(message[148:]);
    }

    /**
     * @notice converts address to bytes32 (alignment preserving cast.)
     * @param addr the address to convert to bytes32
     */
    function addressToBytes32(address addr) public view returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice converts bytes32 to address (alignment preserving cast.)
     * @dev Warning: it is possible to have different input values _buf map to the same address.
     * For use cases where this is not acceptable, validate that the first 12 bytes of _buf are zero-padding.
     * @param _buf the bytes32 to convert to address
     */
    function bytes32ToAddress(bytes32 _buf) public view returns (address) {
        return address(uint160(uint256(_buf)));
    }
}