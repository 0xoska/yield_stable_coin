// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAzUsd} from "./interfaces/IAzUsd.sol";
import {Decoder} from "./libraries/Decoder.sol";

import {IMessageTransmitterV2} from "./interfaces/cctpV2/IMessageTransmitterV2.sol";
import {ITokenMessengerV2} from "./interfaces/cctpV2/ITokenMessengerV2.sol";
import {IPool} from "./interfaces/aave/IPool.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AzUsdCore is ERC20, Ownable, ReentrancyGuard, IAzUsd {
    using SafeERC20 for IERC20;

    uint8 private tokenDecimals;
    uint8 private constant MINIMUM_LIQUIDITY = 100;
    uint16 private referralCode;
    uint16 public rate = 10000;
    address private manager;

    bool public isPause;
    bool public isActiveAave;
    address public aToken;
    address public aavePool;
    address public collateral;
    address public feeReceiver;
    uint128 public refundId;
    uint128 public totalCollateral;

    // The supported Message Format version
    uint32 private constant supportedMessageVersion = 1;
    // The supported Message Body version
    uint32 private constant supportedMessageBodyVersion = 1;
    address public cctpTokenMessagerV2;
    address public cctpMessageTransmitterV2;

    bytes32 private ZEROBYTES32;
    // Byte-length of an address
    uint256 private constant ZERO = 0;
    uint256 private constant ADDRESS_BYTE_LENGTH = 20;

    constructor(
        uint8 _tokenDecimals,
        address _collateral,
        address _cctpTokenMessagerV2,
        address _cctpMessageTransmitterV2,
        address _manager
    ) ERC20("AzUsd Yield Coin", "AZUSD") Ownable(msg.sender) {
        tokenDecimals = _tokenDecimals;
        collateral = _collateral;
        cctpTokenMessagerV2 = _cctpTokenMessagerV2;
        cctpMessageTransmitterV2 = _cctpMessageTransmitterV2;
        manager = _manager;
        allowToken[_collateral] = true;
    }

    mapping(address => bool) public blacklist;

    mapping(address => bool) public allowToken;

    mapping(uint32 => bytes32) public validBytesContract;

    mapping(uint128 => RefundInfo) private refundInfo;

    modifier lock() {
        require(isPause == false, "Paused");
        _;
    }

    modifier onlyManager() {
        _checkManager();
        _;
    }

    function changeManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    function changeRate(uint16 _rate) external onlyOwner {
        require(_rate <= 10000, "Invalid rate");
        rate = _rate;
        emit UpdateRate(rate);
    }

    /**
     * @dev     .Set the target chain address of the contract in the bytes32 type
     * @param   destinationDomain  .
     * @param   targetAddress  .
     */
    function setBytes32ValidContract(
        uint32 destinationDomain,
        bytes32 targetAddress
    ) external onlyOwner {
        validBytesContract[destinationDomain] = targetAddress;
        emit UpdateValidBytesContract(destinationDomain, targetAddress);
    }

    /**
     * @dev     .Set the contract suspension status
     * @param   state  ."true" means pause and "false" means open
     */
    function setPause(bool state) external onlyManager {
        isPause = state;
        emit UpdatePause(isPause);
    }

    /**
     * @dev     .Set the token allowed for minting.
     * @param   tokens  . Allowed token address group
     * @param   states  ."True" indicates permission, while "False" indicates no permission.
     */
    function batchSetAllowToken(
        address[] memory tokens,
        bool[] memory states
    ) external onlyManager {
        require(tokens.length == states.length);
        unchecked {
            for (uint256 i; i < tokens.length; i++) {
                allowToken[tokens[i]] = states[i];
            }
        }
        emit UpdateAllowTokens(tokens, states);
    }

    /**
     * @notice  ."true" indicates a blacklist, while "false" does not
     * @dev     .Set the blacklist information
     * @param   user  .Blacklisted user
     * @param   state  .true indicates a blacklisted user, while false does not
     */
    function setBlacklist(address user, bool state) external onlyManager {
        blacklist[user] = state;
        emit UpdateBlacklist(user, state);
    }

    /**
     * @dev     .The remaining USDC across chains
     * @param   destinationDomain  .
     * @param   minFinalityThreshold  .
     * @param   amount  .
     * @param   maxFee  .
     */
    function crossUSDC(
        uint32 destinationDomain,
        uint32 minFinalityThreshold,
        uint256 amount,
        uint256 maxFee
    ) external onlyManager {
        bytes32 targetContract = validBytesContract[destinationDomain];
        if(targetContract == ZEROBYTES32){
            revert InValidTargetBytes32Contract(targetContract);
        }
        CrossParams memory params;
        params.destinationDomain = destinationDomain;
        params.minFinalityThreshold = minFinalityThreshold;
        params.burnToken = collateral;
        params.mintRecipient = targetContract;
        params.destinationCaller = targetContract;
        params.amount = amount;
        params.maxFee = maxFee;
        _crossUSDC(params);
    }

    /**
     * @dev     .The USDC collateral deposited by users directly enters AaveV3 to earn returns and mints the corresponding amount of azUsd
     * @param   amount  .The quantity of USDC input
     */
    function mint(
        uint32 destinationDomain,
        uint32 minFinalityThreshold,
        address token,
        uint128 amount,
        uint256 maxFee
    ) external nonReentrant lock {
        _checkBlacklist(address(this));
        _checkAllowToken(token);
        //TODO Execute the hook of Uniswap V4 to exchange for USDC

        //Check the quantity of the collateral mint.
        require(amount >= 10000, "The quantity of the collateral is too small.");
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        uint256 mintAmount = getAmountOut(Way.TokenMint, amount);
        _mint(msg.sender, mintAmount);
        totalCollateral += amount;
        uint256 crossAmount = amount * rate / 10000;
        if(crossAmount > 0){
            bytes32 targetContract = validBytesContract[destinationDomain];
            CrossParams memory params;
            params.destinationDomain = destinationDomain;
            params.minFinalityThreshold = minFinalityThreshold;
            params.burnToken = collateral;
            params.mintRecipient = targetContract;
            params.destinationCaller = targetContract;
            params.amount = crossAmount;
            params.maxFee = maxFee;
            _crossUSDC(params);
        }
    }

    /**
     * @notice  . 
     * @dev     .If the user initiates a refund and the current contract's collateral amount is greater than or equal 
     * to the refund amount, the CCTPV2 cross-chain information transmission will not be executed; otherwise, 
     * the cross-chain information transmission will be sent.
     * @param   destinationDomain  .
     * @param   minFinalityThreshold  .
     * @param   amount  .
     * @param   maxFee  .
     */
    function refund(
        uint32 destinationDomain,
        uint32 minFinalityThreshold,
        uint256 amount,
        uint256 maxFee
    ) external nonReentrant {
        _checkRefundState(refundId);
        uint256 refundAmount = getAmountOut(Way.TokenRefund, amount);
        //Check the quantity of the collateral refund.
        // require(refundAmount >= 1000000, "The quantity of the collateral is too small.");
        uint256 collateralBalance = _userTokenBalance(collateral, address(this));
        refundInfo[refundId].refundTime = uint32(block.timestamp);
        refundInfo[refundId].amount = uint64(refundAmount);
        refundInfo[refundId].receiver = msg.sender;
        totalCollateral -= uint128(refundAmount);
        burn(amount);
        if(collateralBalance >= refundAmount){
            IERC20(collateral).safeTransfer(msg.sender, refundAmount);
            refundInfo[refundId].isRefunded = true;
        }else {
            bytes32 targetContract = validBytesContract[destinationDomain];
            //Send cross-chain information for refund  hookdata(RefundId, totalCollateral, amount)
            CrossMessageParams memory params;
            params.destinationDomain = destinationDomain;
            params.recipient = targetContract;
            params.destinationCaller = targetContract;
            params.minFinalityThreshold = minFinalityThreshold;
            params.maxFee = maxFee;
            params.refundAmount = refundAmount;
            _crossMessage(params);
        }
        emit Refund(refundId, msg.sender, refundAmount);
        refundId++;
    }

    /**
     * @notice  .Anyone can trigger
     * @dev     .Receive the information and USDC sent to this contract via cross-chain from the YieldPool contract,
     * and use them to refund to the users.
     * @param   message  .
     * @param   attestation  .
     */
    function receiveUSDCAndData(
        bytes calldata message,
        bytes calldata attestation
    ) external nonReentrant {
        uint32 messageVersion = Decoder.getMessageVersion(message);
        uint32 messageBodyVersion = Decoder.getMessageBodyVersion(message);
        bytes memory hookdata = Decoder.decodeMessageToHookdata(message);
        // Validate message version
        require(
            messageVersion == supportedMessageVersion &&
                messageBodyVersion == supportedMessageBodyVersion,
            "Invalid version"
        );

        //check
        require(address(this) == Decoder.getRecipient(message), "Invalid sender");

        // Relay message
        require(
            IMessageTransmitterV2(cctpMessageTransmitterV2).receiveMessage(
                message,
                attestation
            ),
            "Receive message failed"
        );

        uint128 thisRefundId = abi.decode(hookdata, (uint128));
        uint64 refundAmount = refundInfo[thisRefundId].amount;
        address receiver = refundInfo[thisRefundId].receiver;
        uint256 collateralBalance = _userTokenBalance(collateral, msg.sender);
        _checkRefundState(thisRefundId);
        refundInfo[thisRefundId].isRefunded == true;
        if (collateralBalance >= refundAmount) {
            IERC20(collateral).safeTransfer(
                receiver,
                refundAmount
            );
        } else {
            revert InsufficientBalance(collateralBalance);
        }
        emit TouchCCTPV2Receive(thisRefundId, receiver);
    }

    /**
     * @dev     .The user destroys azUsd
     * @param   amount  .
     */
    function burn(uint256 amount) public {
        uint256 tokenBalance = balanceOf(msg.sender);
        require(amount <= tokenBalance, "Burn overflow");
        _burn(msg.sender, amount);
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    /**
     * @dev     .Obtain the number of tokens obtained from the corresponding mint and refund
     * @param   way  .mint or refund
     * @param   amount  .The number of tokens entered
     * @return  amountOut  .Return the output token corresponding to another token
     */
    function getAmountOut(
        Way way,
        uint256 amount
    ) public view returns (uint256 amountOut) {
        uint8 collateralDecimals = _collateralDecimals();
        if (way == Way.TokenMint && collateralDecimals != 0) {
            if (collateralDecimals == tokenDecimals) {
                amountOut = amount;
            } else if (collateralDecimals > tokenDecimals) {
                amountOut = amount / 10 ** (collateralDecimals - tokenDecimals);
            } else if (collateralDecimals < tokenDecimals) {
                amountOut = amount * 10 ** (tokenDecimals - collateralDecimals);
            }
        } else if (way == Way.TokenRefund && collateralDecimals != 0) {
            if (collateralDecimals == tokenDecimals) {
                amountOut = amount;
            } else if (collateralDecimals > tokenDecimals) {
                amountOut = amount * 10 ** (collateralDecimals - tokenDecimals);
            } else if (collateralDecimals < tokenDecimals) {
                amountOut = amount / 10 ** (tokenDecimals - collateralDecimals);
            }
        } else {
            revert InvalidCollateralDecimals();
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

    function getRefundInfo(uint128 thisRefundId) external view returns (RefundInfo memory) {
        return refundInfo[thisRefundId];
    }

    function _crossUSDC(CrossParams memory params) internal {
        IERC20(collateral).approve(cctpTokenMessagerV2, params.amount);
        ITokenMessengerV2(cctpTokenMessagerV2).depositForBurn(
            params.amount,
            params.destinationDomain,
            params.mintRecipient,
            params.burnToken,
            params.destinationCaller,
            params.maxFee,
            params.minFinalityThreshold
        );
    }

    function _crossMessage(
        CrossMessageParams memory params
    ) internal {
        IERC20(collateral).approve(cctpTokenMessagerV2, params.maxFee);
        bytes memory hookdata = abi.encode(
            refundId,
            totalCollateral,
            params.refundAmount
        );
        IMessageTransmitterV2(cctpMessageTransmitterV2).sendMessage(
            params.destinationDomain, 
            params.recipient, 
            params.destinationCaller, 
            params.minFinalityThreshold, 
            abi.encodePacked(
                supportedMessageBodyVersion, 
                collateral, 
                params.recipient, 
                ZERO, 
                addressToBytes32(address(this)), 
                params.maxFee, 
                ZERO,
                ZERO,
                hookdata
            )
        );
    }

    function _checkManager() private view {
        require(msg.sender == manager, "Non manager");
    }

    function _checkRefundState(uint128 thisRefundId) private view {
        bool state = refundInfo[thisRefundId].isRefunded;
        uint32 refundTime = refundInfo[thisRefundId].refundTime;
        if(state || refundTime >= block.timestamp){
            revert AlreadyRefund("Refunded");
        }
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

    function _checkAllowToken(address token) private view {
        require(allowToken[token], "Invalid token");
    }

    function _checkBlacklist(address user) private view {
        require(
            blacklist[msg.sender] == false && blacklist[user] == false,
            "Blacklist"
        );
    }
}
