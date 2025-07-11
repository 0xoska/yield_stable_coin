// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAzUsdYieldPool} from "./interfaces/IAzUsdYieldPool.sol";
import {Decoder} from "./libraries/Decoder.sol";

import {IMessageTransmitterV2} from "./interfaces/cctpV2/IMessageTransmitterV2.sol";
import {ITokenMessengerV2} from "./interfaces/cctpV2/ITokenMessengerV2.sol";
import {IPool} from "./interfaces/aave/IPool.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AzUsdYieldPool is Ownable, ReentrancyGuard, IAzUsdYieldPool {
    using SafeERC20 for IERC20;

    uint8 private constant MINIMUM_LIQUIDITY = 100;
    uint16 private referralCode;
    address public collateral;

    bool public isPause;
    bool public isActiveAave;
    bool public alarm;
    address public aToken;
    address public aavePool;
    address public feeReceiver;
    uint128 public refundId;
    uint128 public totalCollateral;

    // The supported Message Format version
    uint32 private constant supportedMessageVersion = 1;
    // The supported Message Body version
    uint32 private constant supportedMessageBodyVersion = 1;

    address public cctpTokenMessagerV2;
    address public cctpMessageTransmitterV2;

    // Byte-length of an address
    uint256 private constant ADDRESS_BYTE_LENGTH = 20;

    constructor(
        address _collateral,
        address _cctpTokenMessagerV2, 
        address _cctpMessageTransmitterV2
    ) Ownable(msg.sender) {
        collateral = _collateral;
        cctpTokenMessagerV2 = _cctpTokenMessagerV2;
        cctpMessageTransmitterV2 = _cctpMessageTransmitterV2;
    }

    mapping(uint32 => bytes32) private validContract;

    mapping(uint128 => uint256) private receivedRefundAmount;

    modifier Lock() {
        require(isPause == false, "Paused");
        _;
    }

    function updateAlarm(bool state) external onlyOwner {
        alarm = state;
    }

    /**
     * @dev     .Set the contract suspension status
     * @param   state  ."true" means pause and "false" means open
     */
    function setPause(bool state) external onlyOwner {
        isPause = state;
        emit UpdatePause(isPause);
    }

    function setValidContract(uint32 destinationDomain, bytes32 targetAddress) external onlyOwner {
        validContract[destinationDomain] = targetAddress;
    }

    /**
     * @dev     .Set the AaveV3 information
     * @param   _referralCode  .The default invitation code for AaveV3 is 0
     * @param   _aavePool  .Aavev3 is in the staking pool of this chain
     * @param   _aToken  .The a token generated from the collateral of Aavev3
     * @param   _isActiveAave  .The aavev3 switch, true means it is not turned on, 
     *          false means it is not turned on, and it is not turned on by default
     */
    function setAaveInfo(
        uint16 _referralCode,
        address _aavePool,
        address _aToken,
        bool _isActiveAave
    ) external onlyOwner {
        referralCode = _referralCode;
        aavePool = _aavePool;
        aToken = _aToken;
        isActiveAave = _isActiveAave;
    }

    /**
     * @dev     .Set the fee receiver
     * @param   _feeReceiver  .Fee recipient
     */
    function setFeeReceiver(
        address _feeReceiver
    ) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice  .
     * @dev     .
     */
    function aaveSupllyAll() external onlyOwner {
        //supply to aaveV3
        uint256 currentBalance = _userTokenBalance(collateral, address(this));
        if(currentBalance > 0){
            require(_aaveSupply(currentBalance), "Aave supply fail");
        }
    }
    
    /**
     * @dev     .Extract all USDC from AaveV3
     */
    function aaveWithdrawAll() external onlyOwner {
        require(_aaveWithdraw(), "Aave withdraw fail");
    }

    /**
     * @notice  .
     * @dev     .
     * @param   destinationDomain  .
     * @param   minFinalityThreshold  .
     * @param   maxFee  .
     */
    function crossAllUSDC(
        uint32 destinationDomain, 
        uint32 minFinalityThreshold, 
        uint256 maxFee
    ) external onlyOwner {
        uint256 collateralBalance = _userTokenBalance(collateral, address(this));
        if(collateralBalance > 0){
            bytes32 targetContract = validContract[destinationDomain];
            require(targetContract.length > 0, "Invalid valid contract");
            CrossParams memory params;
            params.destinationDomain = destinationDomain; 
            params.minFinalityThreshold = minFinalityThreshold;
            params.burnToken = collateral;
            params.mintRecipient = targetContract;
            params.destinationCaller = targetContract;
            params.amount = collateralBalance;
            params.maxFee = maxFee;
            _crossUSDCAndData(params);
        }else {
            revert BalanceZero();
        }
    }

    function crossUSDC(
        uint32 destinationDomain, 
        uint32 minFinalityThreshold, 
        uint256 maxFee,
        uint128 thisRefundId
    ) external {
        uint256 refundAmount = receivedRefundAmount[thisRefundId];
        if(refundAmount > 0 && alarm == false){
            //Extract all collateral from Aave
            uint256 aTokenBalance = _userTokenBalance(aToken, address(this));
            if(aTokenBalance > 0){
                require(_aaveWithdraw(), "Aave withdraw fail");
            }
            uint256 collateralBalance = _userTokenBalance(collateral, address(this));
            //Determine whether an emergency situation has occurred
            if(collateralBalance >= refundAmount){
                bytes32 targetContract = validContract[destinationDomain];
                require(targetContract.length > 0, "Invalid valid contract");
                //Execute CCTP cross-chain operation
                CrossParams memory params;
                params.destinationDomain = destinationDomain; 
                params.minFinalityThreshold = minFinalityThreshold;
                params.burnToken = collateral;
                params.mintRecipient = targetContract;
                params.destinationCaller = targetContract;
                params.amount = refundAmount;
                params.maxFee = maxFee;
                params.hookData = abi.encode(
                    thisRefundId
                );
                _crossUSDCAndData(params);

                //The remaining collateral continues to generate income.
                if(collateralBalance > 0){
                    require(_aaveSupply(collateralBalance), "Aave supply fail");
                }
                delete receivedRefundAmount[thisRefundId];      
            } else {
                alarm = true;
                emit Emergency(thisRefundId, refundAmount, collateralBalance);
            }
        }else {
            revert BalanceZero();
        }
    }

    function receiveUSDCOrData(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        uint32 messageVersion = Decoder.getMessageVersion(message);
        uint32 messageBodyVersion = Decoder.getMessageBodyVersion(message);
        bytes memory hookdata = Decoder.decodeMessageToHookdata(message);
        // Validate message version
        require(
            messageVersion == supportedMessageVersion && messageBodyVersion == supportedMessageBodyVersion,
            "Invalid version"
        );

        // Relay message
        require(IMessageTransmitterV2(cctpMessageTransmitterV2).receiveMessage(
            message,
            attestation
        ), "Receive message failed");

        if(hookdata.length > 0){
            (
                uint128 thisRefundId, 
                uint128 currentTotalCollateral, 
                uint256 refundAmount
            ) = abi.decode(hookdata,(uint128, uint128, uint256));
            receivedRefundAmount[thisRefundId] = refundAmount;
            totalCollateral = currentTotalCollateral;
            emit ReceiveRefundInfo(thisRefundId, refundAmount);
        }
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

    function _aaveSupply(uint256 amount) private returns (bool state) {
        IERC20(collateral).approve(aavePool, amount);
        IPool(aavePool).deposit(
            collateral,
            amount,
            address(this),
            referralCode
        );
        state = true;
    }

    function _aaveWithdraw() private returns (bool state) {
        IERC20(aToken).approve(aavePool, type(uint256).max);
        IPool(aavePool).withdraw(collateral, type(uint256).max, address(this));
        uint256 currentCollateralBalance = _userTokenBalance(
            collateral,
            address(this)
        );
        if (currentCollateralBalance > totalCollateral + MINIMUM_LIQUIDITY && totalCollateral > 0) {
            uint256 profit = currentCollateralBalance -
                totalCollateral -
                MINIMUM_LIQUIDITY;
            IERC20(collateral).safeTransfer(feeReceiver, profit);
        }
        IERC20(aToken).approve(aavePool, 0);
        state = true;
    }

    function _crossUSDCAndData(
        CrossParams memory params
    ) internal {
        IERC20(collateral).approve(cctpTokenMessagerV2, params.amount);
        ITokenMessengerV2(cctpTokenMessagerV2).depositForBurnWithHook(
            params.amount,
            params.destinationDomain,
            params.mintRecipient,
            params.burnToken,
            params.destinationCaller,
            params.maxFee,
            params.minFinalityThreshold,
            params.hookData
        );
    }

    function _collateralDecimals()
        private
        view
        returns (uint8 _thisCollateralDecimals)
    {
        _thisCollateralDecimals = IERC20Metadata(collateral).decimals();
    }

    function _userTokenBalance(
        address token,
        address account
    ) private view returns (uint256 _userBalance) {
        _userBalance = IERC20(token).balanceOf(account);
    }
    
}
