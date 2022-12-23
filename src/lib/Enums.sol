// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

enum ApprovalType {
    ERC20_APPROVE,
    INCREASE_ALLOWANCE,
    ERC721_APPROVE,
    SET_APPROVAL_FOR_ALL
}

enum TokenType {
    ERC20,
    ERC721,
    ERC1155
}
