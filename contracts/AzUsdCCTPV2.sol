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

        bytes memory message = abi.encode(mintRecipient, amount);
        bytes memory hookData = abi.encode( 
            targetBytes32AzUsd, // Receiving contract verification
            message // Custom information
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

    event TouchReceive(address receiver, uint256 amount);

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

        // Handle hook if present
        bytes29 _hookData = BurnMessageV2._getHookData(_msgBody);
        if (_hookData.isValid()) {
            uint256 _hookDataLength = _hookData.len();
            if (_hookDataLength >= ADDRESS_BYTE_LENGTH) {
                address _target = _hookData.indexAddress(0);
                bytes memory _hookCalldata = _hookData
                    .postfix(_hookDataLength - ADDRESS_BYTE_LENGTH, 0)
                    .clone();

                // (hookSuccess, hookReturnData) = _executeHook(
                //     _target,
                //     _hookCalldata
                // );
                
                (bytes32 bytes32Receiver, uint256 amount) = abi.decode(_hookCalldata, (bytes32, uint256));
                address receiver = bytes32ToAddress(bytes32Receiver);
                emit TouchReceive(receiver, amount);
            }
        }
    }

    // ============ Internal Functions  ============
    /**
     * @notice Handles hook data by executing a call to a target address
     * @dev Can be overridden to customize execution behavior
     * @dev Does not revert if the CALL to the hook target fails
     * @param _hookTarget The target address of the hook
     * @param _hookCalldata The hook calldata
     * @return _success True if the call to the encoded hook target succeeds
     * @return _returnData The data returned from the call to the hook target
     */
    function _executeHook(
        address _hookTarget,
        bytes memory _hookCalldata
    ) internal virtual returns (bool _success, bytes memory _returnData) {
        (_success, _returnData) = address(_hookTarget).call(_hookCalldata);
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