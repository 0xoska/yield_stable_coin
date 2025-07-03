// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPool} from "./interfaces/aave/IPool.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract YieldStableCoinCore is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 private tokenDecimals;
    uint16 private constant MINIMUM_LIQUIDITY = 1000;
    uint16 private referralCode;
    uint64 private flowFee;
    address public collateral;
    address public aToken;
    address public aavePool;
    address public feeReceiver;
    uint256 public flowId;
    uint256 public totalCollateral;

    constructor(
        uint8 _tokenDecimals,
        address _collateral
    )
    ERC20("Yield StableCoin", "YUSD") 
    Ownable(msg.sender)
    {   
        tokenDecimals = _tokenDecimals;
        collateral = _collateral;
        _mint(msg.sender, 10000000 ether);
    }

    struct FlowInfo{
        uint64 startTime;
        uint64 lastestWithdrawTime;
        uint64 endTime;
        address sender;
        address receiver;
        uint128 flowAmount; 
        uint128 alreadyWithdrawAmount;
    }
    
    mapping(uint256 => FlowInfo) private flowInfo;

    enum Way{TokenMint, TokenRefund, TokenSafeTransfer, TokenStream}

    event Refund(address user, uint256 amount);
    event Flow(address sender, address receiver, uint256 amount);
    event Release(address receiver, uint256 amount);

    function setAaveInfo(
        uint16 _referralCode,
        address _aavePool,
        address _aToken
    ) external onlyOwner {
        referralCode = _referralCode;
        aavePool = _aavePool;
        aToken = _aToken;
    }

    function setFeeInfo(
        uint64 _flowFee,
        address _feeReceiver
    ) external onlyOwner {
        flowFee = _flowFee;
        feeReceiver = _feeReceiver;
    }

    function mint(
        Way way, 
        uint256 amount
    ) external nonReentrant {
        uint256 collateralBalance = _userCollateralBalance(msg.sender);
        require(collateralBalance >= amount, "Collateral insufficient");
        uint256 mintAmount = getAmount(way, amount);
        _mint(msg.sender, mintAmount);
        totalCollateral += amount;
        require(_aaveSupply(amount), "Aave supply fail");
    }

    function refund(
        Way way, 
        uint256 amount
    ) external nonReentrant {
        uint256 refundAmount = getAmount(way, amount);
        require(_aaveWithdraw(), "Aave withdraw fail");
        IERC20(collateral).safeTransfer(msg.sender, refundAmount);
        burn(amount);
        totalCollateral -= refundAmount;
        uint256 collateralBalance = _userCollateralBalance(address(this));
        require(_aaveSupply(collateralBalance), "Aave supply fail");
        emit Refund(msg.sender, refundAmount);
    }

    function flow(
        Way way, 
        address receiver, 
        uint64 endTime, 
        uint128 amount
    ) external payable {
        uint256 userTokenBalance = balanceOf(msg.sender);
        require(userTokenBalance >= amount, "Insufficient");
        if(way == Way.TokenSafeTransfer) {
            transfer(receiver, amount);
        } else if(way == Way.TokenStream){
            uint64 currentime = uint64(block.timestamp);
            _burn(msg.sender, amount);
            flowInfo[flowId] = FlowInfo({
                startTime: currentime,
                lastestWithdrawTime: 0,
                endTime: currentime + endTime,
                sender: msg.sender,
                receiver: receiver,
                flowAmount: amount,
                alreadyWithdrawAmount: 0
            });
            flowId++;
        }else {
            revert("Invalid flow way");
        }
        emit Flow(msg.sender, receiver, amount);
    }

    function release(uint256 thisFlowId) external nonReentrant {
        uint64 currentTime = uint64(block.timestamp);
        address receiver = flowInfo[thisFlowId].receiver;
        require(msg.sender == receiver, "Not this receiver");
        uint128 residue = getStreamBalance(thisFlowId);
        require(residue > 0, "Zero");
        _mint(receiver, residue);
        flowInfo[thisFlowId].lastestWithdrawTime = currentTime;
        flowInfo[thisFlowId].alreadyWithdrawAmount = residue;
        emit Release(msg.sender, residue);
    }

    function burn(uint256 amount) public {
        uint256 tokenBalance = balanceOf(msg.sender);
        require(amount <= tokenBalance, "Burn overflow");
        _burn(msg.sender, amount);
    }

    

    function _aaveSupply(uint256 amount) private returns (bool state) {
        IPool(aavePool).deposit(collateral, amount, address(this), referralCode);
        state = true;
    }

    function _aaveWithdraw() private returns (bool state) {
        IERC20(aToken).approve(aavePool, type(uint256).max);
        IPool(aavePool).withdraw(collateral, type(uint256).max, address(this));
        uint256 currentCollateralBalance = _userCollateralBalance(address(this));
        if(currentCollateralBalance > totalCollateral + MINIMUM_LIQUIDITY){
            uint256 profit = currentCollateralBalance - totalCollateral - MINIMUM_LIQUIDITY;
            IERC20(collateral).safeTransfer(feeReceiver, profit);
        }
        IERC20(aToken).approve(aavePool, 0);
        state = true;
    }

    function decimals() public override view returns (uint8){
        return tokenDecimals;
    }

    function getAmount(
        Way way, 
        uint256 amount
    ) public view returns (uint256 amountOut) {
        uint8 collateralDecimals = _collateralDecimals();
        if(way == Way.TokenMint && collateralDecimals != 0) {
            if(collateralDecimals == tokenDecimals) {
                amountOut = amount;
            } else if(collateralDecimals > tokenDecimals) {
                amountOut = amount / (collateralDecimals - tokenDecimals);
            } else if(collateralDecimals < tokenDecimals) {
                amountOut = amount * (tokenDecimals - collateralDecimals);
            }
        }else if(way == Way.TokenRefund && collateralDecimals != 0) {
            if(collateralDecimals == tokenDecimals) {
                amountOut = amount;
            } else if(collateralDecimals > tokenDecimals) {
                amountOut = amount * (collateralDecimals - tokenDecimals);
            } else if(collateralDecimals < tokenDecimals) {
                amountOut = amount / (tokenDecimals - collateralDecimals);
            }
        }else {
            revert ("Invalid collateral decimals");
        }
    }

    function getStreamBalance(uint256 thisFlowId) public view returns (uint128 residue) {
        uint64 startTime = flowInfo[thisFlowId].startTime;
        uint64 endTime = flowInfo[thisFlowId].endTime;
        uint64 currentTime = uint64(block.timestamp);
        uint64 lastestWithdrawTime = flowInfo[thisFlowId].lastestWithdrawTime;
        require(currentTime <= flowInfo[thisFlowId].endTime, "Already end");
        uint128 amount = flowInfo[thisFlowId].flowAmount;
        uint128 alreadyWithdrawAmount = flowInfo[thisFlowId].alreadyWithdrawAmount;
        if(endTime - startTime > 0){
            if(amount >= alreadyWithdrawAmount){
                uint128 quantityPerSecond = amount / (endTime - startTime);
                if (currentTime >= endTime) {
                    residue = amount - alreadyWithdrawAmount;
                } else {
                    if(lastestWithdrawTime == 0){
                        residue = (currentTime - startTime) *
                        quantityPerSecond;
                    }else{
                        if(lastestWithdrawTime > startTime && lastestWithdrawTime < endTime) {
                            residue = (currentTime - lastestWithdrawTime) *
                        quantityPerSecond;
                        }
                    }
                    
                }
            }
        }
    }

    function getFlowInfo(uint256 thisFlowId) external view returns (FlowInfo memory) {
        return flowInfo[thisFlowId];
    } 

    function _collateralDecimals() private view returns (uint8 _thisCollateralDecimals) {
        _thisCollateralDecimals = IERC20Metadata(collateral).decimals();
    }

    function _userCollateralBalance(address user) private view returns (uint256 _collateralBalance) {
        _collateralBalance = IERC20(collateral).balanceOf(user);
    }


}
