// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Approvals

// bytes4(keccak256("approve(address,uint256)"))
uint256 constant IERC20_721_APPROVE_SELECTOR = 0x095ea7b300000000000000000000000000000000000000000000000000000000;
// bytes4(keccak256("increaseAllowance(address,uint256)"))
uint256 constant IERC20_NONSTANDARD_INCREASE_ALLOWANCE_SELECTOR =
    0x3950935100000000000000000000000000000000000000000000000000000000;
// bytes4(keccak256("setApprovalForAll(address,bool)"))
uint256 constant IERC721_1155_SET_APPROVAL_FOR_ALL_SELECTOR =
    0xa22cb46500000000000000000000000000000000000000000000000000000000;

uint256 constant SELECTOR_MASK = 0xffffffff00000000000000000000000000000000000000000000000000000000;