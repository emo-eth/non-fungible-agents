// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC173} from "./IERC173.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";
import {NotOwner} from "./lib/Errors.sol";

abstract contract TokenOwnable is IERC173, Context {
    function owner() public view override returns (address) {
        return _getTokenContract().ownerOf(_getTokenId());
    }

    function _onlyOwner() internal view virtual {
        if (_msgSender() != owner()) {
            revert NotOwner();
        }
    }

    function _getTokenContract() internal view virtual returns (IERC721);

    function _getTokenId() internal view virtual returns (uint256);
}
