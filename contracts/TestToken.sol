//SPDX-License-Identifier: MIT

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    uint8 private immutable currentDecimals;

    constructor (string memory thisName, string memory thisSymbol, uint8 thisDecimals)ERC20(thisName, thisSymbol){
        currentDecimals = thisDecimals;
    }

    function decimals() public override view returns (uint8) {
        return currentDecimals;
    }
}