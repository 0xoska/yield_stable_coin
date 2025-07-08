// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAzUsd} from "./interfaces/IAzUsd.sol";

import {IPool} from "./interfaces/aave/IPool.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AzUsdCore is ERC20, Ownable, ReentrancyGuard, IAzUsd {
    using SafeERC20 for IERC20;

    uint8 private tokenDecimals;
    uint8 private constant MINIMUM_LIQUIDITY = 100;
    uint16 private referralCode;
    uint64 private flowFee;
    address public collateral;

    bool public isPause;
    bool public isActiveAave;
    address public aToken;
    address public aavePool;
    address public feeReceiver;
    uint256 public flowId;
    uint256 public totalCollateral;

    constructor(
        uint8 _tokenDecimals,
        address _collateral
    ) ERC20("AzUsd Yield Coin", "AZUSD") Ownable(msg.sender) {
        tokenDecimals = _tokenDecimals;
        collateral = _collateral;
        _mint(msg.sender, 10000000 ether);
    }

    mapping(uint256 => FlowInfo) private flowInfo;

    mapping(address => uint256[]) private userFlowIds;

    mapping(address => bool) private blacklist;

    modifier Lock() {
        require(isPause == false, "Paused");
        _;
    }

    function setPause(bool state) external onlyOwner {
        isPause = state;
        emit UpdatePause(isPause);
    }

    function setBlacklist(address user, bool state) external onlyOwner {
        blacklist[user] = state;
        emit UpdateBlacklist(user, state);
    }

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

    function setFeeInfo(
        uint64 _flowFee,
        address _feeReceiver
    ) external onlyOwner {
        flowFee = _flowFee;
        feeReceiver = _feeReceiver;
    }
    
    function exitAave() external onlyOwner {
        require(_aaveWithdraw(), "Aave withdraw fail");
    }

    function mint(Way way, uint256 amount) external nonReentrant Lock {
        _checkBlacklist(address(this));
        uint256 collateralBalance = _userCollateralBalance(collateral, msg.sender);
        require(collateralBalance >= amount, "Collateral insufficient");
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        uint256 mintAmount = getAmountOut(way, amount);
        _mint(msg.sender, mintAmount);
        totalCollateral += amount;
        if(isActiveAave){
            require(_aaveSupply(amount), "Aave supply fail");
        }
    }

    function refund(Way way, uint256 amount) external nonReentrant {
        uint256 refundAmount = getAmountOut(way, amount);
        uint256 aTokenBalance = _userCollateralBalance(aToken, address(this));
        if(isActiveAave){
            if(aTokenBalance > 0){
                require(_aaveWithdraw(), "Aave withdraw fail");
            }
        }
        IERC20(collateral).safeTransfer(msg.sender, refundAmount);
        burn(amount);
        totalCollateral -= refundAmount;
        uint256 collateralBalance = _userCollateralBalance(collateral, address(this));
        
        if(isActiveAave){
            if(collateralBalance > 0){
                require(_aaveSupply(collateralBalance), "Aave supply fail");
            }
        }
        emit Refund(msg.sender, refundAmount);
    }

    function flow(
        Way way,
        address receiver,
        uint64 endTime,
        uint128 amount
    ) external payable nonReentrant Lock {
        _checkBlacklist(receiver);
        require(msg.value >= flowFee, "Insufficient fee");
        uint256 userTokenBalance = balanceOf(msg.sender);
        require(userTokenBalance >= amount, "Insufficient");
        require(msg.sender != receiver && receiver != address(0), "Invalid address");
        require(endTime >= 60, "At least 1 min");
        if (way == Way.TokenSafeTransfer) {
            _burn(msg.sender, amount);
            _mint(receiver, amount);
        } else if (way == Way.TokenStream) {
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
            userFlowIds[receiver].push(flowId);
            emit Stream(flowId);
            flowId++;
        } else {
            revert("Invalid flow way");
        }
        if (flowFee > 0) {
            (bool suc, ) = feeReceiver.call{value: msg.value}("");
            require(suc, "Receive fee fail");
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
        uint256 currentCollateralBalance = _userCollateralBalance(
            collateral,
            address(this)
        );
        if (currentCollateralBalance > totalCollateral + MINIMUM_LIQUIDITY) {
            uint256 profit = currentCollateralBalance -
                totalCollateral -
                MINIMUM_LIQUIDITY;
            IERC20(collateral).safeTransfer(feeReceiver, profit);
        }
        IERC20(aToken).approve(aavePool, 0);
        state = true;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

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

    function getStreamBalance(
        uint256 thisFlowId
    ) public view returns (uint128 residue) {
        uint64 startTime = flowInfo[thisFlowId].startTime;
        uint64 endTime = flowInfo[thisFlowId].endTime;
        uint64 currentTime = uint64(block.timestamp);
        uint64 lastestWithdrawTime = flowInfo[thisFlowId].lastestWithdrawTime;
        require(currentTime <= flowInfo[thisFlowId].endTime, "Already end");
        uint128 amount = flowInfo[thisFlowId].flowAmount;
        uint128 alreadyWithdrawAmount = flowInfo[thisFlowId]
            .alreadyWithdrawAmount;
        if (endTime - startTime > 0) {
            if (amount >= alreadyWithdrawAmount) {
                uint128 quantityPerSecond = amount / (endTime - startTime);
                if (currentTime >= endTime) {
                    residue = amount - alreadyWithdrawAmount;
                } else {
                    if (lastestWithdrawTime == 0) {
                        residue = (currentTime - startTime) * quantityPerSecond;
                    } else {
                        if (
                            lastestWithdrawTime > startTime &&
                            lastestWithdrawTime < endTime
                        ) {
                            residue =
                                (currentTime - lastestWithdrawTime) *
                                quantityPerSecond;
                        }
                    }
                }
            }
        }
    }

    function getFlowInfo(
        uint256 thisFlowId
    ) public view returns (FlowInfo memory) {
        return flowInfo[thisFlowId];
    }

    function getUserFlowIdsLength(
        address user
    ) public view returns (uint256) {
        return userFlowIds[user].length;
    }

    function indexUserStreams(
        address user,
        uint256 pageIndex
    )
        external
        view
        returns (
            uint256[] memory flowIdGroup,
            uint256[] memory streamBalanceGroup,
            FlowInfo[] memory flowInfoGroup
        )
    {
        uint256 userFlowIdslength = getUserFlowIdsLength(user);
        if (userFlowIdslength > 0) {
            uint256 len;
            uint256 indexFlowId;
            uint256 currentFlowId;
            require(pageIndex <= userFlowIdslength / 10, "Page index overflow");
            if (userFlowIdslength <= 10) {
                len = userFlowIdslength;
            } else {
                if (userFlowIdslength % 10 == 0) {
                    len = 10;
                } else {
                    len = userFlowIdslength % 10;
                }
                if (pageIndex > 0) {
                    indexFlowId = pageIndex * 10;
                    currentFlowId = userFlowIds[user][indexFlowId];
                }
            }
            flowIdGroup = new uint256[](len);
            streamBalanceGroup = new uint256[](len);
            flowInfoGroup = new FlowInfo[](len);
            unchecked {
                for (uint256 i; i < len; i++) {
                    flowIdGroup[i] = currentFlowId;
                    streamBalanceGroup[i] = getStreamBalance(currentFlowId);
                    flowInfoGroup[i] = getFlowInfo(currentFlowId);
                    currentFlowId++;
                }
            }
        }
    }

    function _collateralDecimals()
        private
        view
        returns (uint8 _thisCollateralDecimals)
    {
        _thisCollateralDecimals = IERC20Metadata(collateral).decimals();
    }

    function _userCollateralBalance(
        address token,
        address user
    ) private view returns (uint256 _collateralBalance) {
        _collateralBalance = IERC20(token).balanceOf(user);
    }

    function _checkBlacklist(address user) private view {
        require(
            blacklist[msg.sender] == false && blacklist[user] == false,
            "Blacklist"
        );
    }
}
