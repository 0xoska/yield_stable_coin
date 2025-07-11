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
    address public collateral;

    bool public isPause;
    bool public isActiveAave;
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
        uint8 _tokenDecimals,
        address _collateral,
        address _cctpTokenMessagerV2, 
        address _cctpMessageTransmitterV2
    ) ERC20("AzUsd Yield Coin", "AZUSD") Ownable(msg.sender) {
        tokenDecimals = _tokenDecimals;
        collateral = _collateral;
        cctpTokenMessagerV2 = _cctpTokenMessagerV2;
        cctpMessageTransmitterV2 = _cctpMessageTransmitterV2;
        _mint(msg.sender, 10000000 ether);
    }

    mapping(address => bool) private blacklist;

    mapping(address => bool) private allowToken;

    mapping(uint32 => bytes32) private validContract;

    mapping(uint128 => RefundInfo) private refundInfo;

    modifier Lock() {
        require(isPause == false, "Paused");
        _;
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
     * @dev     .Set the token allowed for minting.
     * @param   tokens  . Allowed token address group
     * @param   states  ."True" indicates permission, while "False" indicates no permission.
     */
    function batchSetAllowToken(address[] memory tokens, bool[] memory states) external onlyOwner {
        require(tokens.length == states.length);
        unchecked {
            for(uint256 i; i<tokens.length; i++){
                allowToken[tokens[i]] = states[i];
                emit UpdateAllowToken(tokens[i], states[i]);
            }
        }
    }

    /**
     * @notice  ."true" indicates a blacklist, while "false" does not
     * @dev     .Set the blacklist information
     * @param   user  .Blacklisted user
     * @param   state  .true indicates a blacklisted user, while false does not
     */
    function setBlacklist(address user, bool state) external onlyOwner {
        blacklist[user] = state;
        emit UpdateBlacklist(user, state);
    }

    function crossUSDC(uint32 destinationDomain, uint32 minFinalityThreshold, uint256 thisRefundId) external onlyOwner {

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
    ) external nonReentrant Lock {
        _checkBlacklist(address(this));
        _checkAllowToken(token);
        uint256 userCollateralBalance = _userTokenBalance(collateral, msg.sender);
        require(userCollateralBalance >= amount, "Collateral insufficient");
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        uint256 mintAmount = getAmountOut(Way.TokenMint, amount);
        _mint(msg.sender, mintAmount);
        totalCollateral += amount;
        uint256 collateralBalance = _userTokenBalance(collateral, msg.sender);
        bytes32 targetContract = validContract[destinationDomain];
        CrossParams memory params;
        params.destinationDomain = destinationDomain; 
        params.minFinalityThreshold = minFinalityThreshold;
        params.burnToken = collateral;
        params.mintRecipient = targetContract;
        params.destinationCaller = targetContract;
        params.amount = collateralBalance;
        params.maxFee = maxFee;
        _crossUSDCAndData(params);
    }

    function receiveUSDCAndData(
        bytes calldata message,
        bytes calldata attestation
    ) internal {
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


    }

    /**
     * @dev     .Withdraw all the USDC stored in AaveV3 and calculate whether the current amount of USDC obtained is 
     **         greater than the total amount of staked USDC + MINIMUM_LIQUIDITY
     * @param   amount  .The quantity of azUSD input
     */
    function refund(
        uint256 amount, 
        uint32 destinationDomain, 
        uint32 minFinalityThreshold,
        uint256 maxFee
    ) external nonReentrant {
        uint256 refundAmount = getAmountOut(Way.TokenRefund, amount);

        refundInfo[refundId].refundTime = uint32(block.timestamp);
        refundInfo[refundId].amount = uint64(refundAmount);
        refundInfo[refundId].receiver = msg.sender;
        totalCollateral -= uint128(refundAmount);

        // send cctpV2 message(RefundId, totalCollateral, amount)
        bytes32 targetContract = validContract[destinationDomain];
        CrossParams memory params;
        params.destinationDomain = destinationDomain; 
        params.minFinalityThreshold = minFinalityThreshold;
        params.burnToken = collateral;
        params.mintRecipient = targetContract;
        params.destinationCaller = targetContract;
        params.amount = 0;
        params.maxFee = maxFee;
        params.hookData = abi.encode(
            refundId, totalCollateral, refundAmount
        );
        _crossUSDCAndData(params);

        burn(amount);
        emit Refund(refundId, msg.sender, refundAmount);
        refundId++;
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
                amountOut = amount * 10 **  (tokenDecimals - collateralDecimals);
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
            revert("Invalid collateral decimals");
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
