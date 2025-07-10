// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IMessageTransmitterV2} from "./interfaces/cctpV2/IMessageTransmitterV2.sol";
import {ITokenMessengerV2} from "./interfaces/cctpV2/ITokenMessengerV2.sol";
import {TypedMemView} from "./libraries/TypedMemView.sol";
import {MessageV2} from "./libraries/cctpV2/MessageV2.sol";
import {BurnMessageV2} from "./libraries/cctpV2/BurnMessageV2.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
contract AzUsdCCTPV2 {

    using SafeERC20 for IERC20;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // The supported Message Format version
    uint32 public constant supportedMessageVersion = 1;
    // The supported Message Body version
    uint32 public constant supportedMessageBodyVersion = 1;
    // Byte-length of an address
    uint256 internal constant ADDRESS_BYTE_LENGTH = 20;

    address public cctpTokenMessagerV2;
    address public cctpMessageTransmitterV2;

    constructor(address _cctpTokenMessagerV2, address _cctpMessageTransmitterV2){
        cctpTokenMessagerV2 = _cctpTokenMessagerV2;
        cctpMessageTransmitterV2 = _cctpMessageTransmitterV2;
    }

    mapping(bytes32 => bool) private validBytes32AzUsdContract;

    function setValidContract(bytes32 bytes32AzUsd, bool state) external {
        validBytes32AzUsdContract[bytes32AzUsd] = state;
    }

    function cross(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 targetBytes32AzUsd,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) public {
        require(validBytes32AzUsdContract[targetBytes32AzUsd], "Invalid target azUsdContract");
        IERC20(burnToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(burnToken).approve(cctpTokenMessagerV2, amount);

        bytes memory hookData = abi.encode( 
            msg.sender, 
            uint64(amount)
        );

        ITokenMessengerV2(cctpTokenMessagerV2).depositForBurnWithHook(
            amount,
            destinationDomain,
            targetBytes32AzUsd,
            burnToken,
            bytes32(0),
            maxFee,
            minFinalityThreshold,
            hookData
        );
    }

    function sendCircleMessage(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata messageBody
    ) public {
        IMessageTransmitterV2(cctpMessageTransmitterV2).sendMessage(
            destinationDomain,
            recipient,
            destinationCaller,
            minFinalityThreshold,
            messageBody
        );
    }

    event TouchData(bytes data);
    event TouchHookData(bytes hookData);
    uint256 public receiveAmount;
    address public receiver;

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

      uint32 _version,
        uint32 _sourceDomain,
        uint32 _destinationDomain,
        bytes32 _sender,
        bytes32 _recipient,
        bytes32 _destinationCaller,
        uint32 _minFinalityThreshold,
        bytes calldata _messageBody
     */
    function receiveUSDC(
        bytes calldata message,
        bytes calldata attestation
    ) public {

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

        // Relay message
        require(IMessageTransmitterV2(cctpMessageTransmitterV2).receiveMessage(
            message,
            attestation
        ), "Receive message failed");

        bytes memory hookdata = decodeMessageToHookdata(message);
                // (receiver, receiveAmount) = abi.decode(_hookData, (address, uint64));
                // emit TouchData(_hookData);
        emit TouchHookData(hookdata);
        
    }

    struct MessageHeader{
       uint32 version;
       uint32 sourceDomain;
       uint32 destinationDomain;
       bytes32 nonce;
       bytes32 sender;
       bytes32 recipient;
       bytes32 destinationCaller;
       uint32 minFinalityThreshold;
       uint32 finalityThresholdExecuted;
       bytes messageBody;
    }

    function decodeMessage(bytes calldata message) public view returns(MessageHeader memory) {
        return MessageHeader({
            version: uint32(bytes4(message[0:4])),
            sourceDomain: uint32(bytes4(message[4:8])),
            destinationDomain: uint32(bytes4(message[8:12])),
            nonce: bytes32(message[12:44]),
            sender: bytes32(message[44:76]),
            recipient: bytes32(message[76:108]),
            destinationCaller: bytes32(message[108:140]),
            minFinalityThreshold: uint32(bytes4(message[140:144])),
            finalityThresholdExecuted: uint32(bytes4(message[144:148])),
            messageBody: message[148:]
        });
    }

    struct MessageBody{
        uint32 version;
        bytes32 burnToken;
        bytes32 mintRecipient;
        uint256 amount;
        bytes32 messageSender;
        uint256 maxFee;
        uint256 feeExecuted;
        uint256 expirationBlock;
        bytes hookData;
    }

    function decodeMessageBody(bytes calldata messageBody) public view returns (MessageBody memory) {
        return MessageBody({
            version: uint32(bytes4(messageBody[0:4])),
            burnToken: bytes32(messageBody[4:36]),
            mintRecipient: bytes32(messageBody[36:68]),
            amount: uint256(bytes32(messageBody[68: 100])),
            messageSender: bytes32(messageBody[100:132]),
            maxFee: uint256(bytes32(messageBody[132: 164])),
            feeExecuted: uint256(bytes32(messageBody[164: 196])),
            expirationBlock: uint256(bytes32(messageBody[196: 228])),
            hookData: messageBody[228:]
        });
    }

    function decodeMessageToHookdata(bytes calldata message) public view returns (bytes memory hookdata) {
        hookdata = message[376:];
    }


    function cctpV2HandleReceiveFinalizedMessage(
        uint32 remoteDomain,
        bytes32 sender,
        uint32,
        bytes calldata messageBody
    ) public {
        bool state = ITokenMessengerV2(cctpTokenMessagerV2).handleReceiveFinalizedMessage(
            remoteDomain,
            sender,
            2000,
            messageBody
        );
        require(state, "Handle fail");
    }

    function cctpV2HandleReceiveUnfinalizedMessage(
        uint32 remoteDomain,
        bytes32 sender,
        uint32 finalityThresholdExecuted,
        bytes calldata messageBody
    ) public {
        bool state = ITokenMessengerV2(cctpTokenMessagerV2).handleReceiveUnfinalizedMessage(
            remoteDomain,
            sender,
            finalityThresholdExecuted,
            messageBody
        );
        require(state, "Handle fail");
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