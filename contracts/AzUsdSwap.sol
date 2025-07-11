// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IV4Router} from "./interfaces/uniswapV4/IV4Router.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AzUsdSwap {
    using SafeERC20 for IERC20;

    // function swap(address v4Router, address tokenIn, uint256 amountIn) external {
    //     ExactInputSingleParams memory params = ExactInputSingleParams({
    //         poolKey:
    //         zeroForOne:
    //         amountIn:
    //         amountOutMinimum:
    //         hookData:
    //     })
    //     IV4Router(v4Router).ExactInputSingleParams();
    // }

}