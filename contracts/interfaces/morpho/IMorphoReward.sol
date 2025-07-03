// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface IMorphoReward {

    function claim(address account, address reward, uint256 claimable, bytes32[] calldata proof) external returns (uint256 amount);

}