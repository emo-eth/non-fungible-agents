// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clone} from "create2-clones-with-immutable-args/Clone.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {Executable} from "./Executable.sol";
import {TokenOwnable} from "./TokenOwnable.sol";
import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";
import {AccountFrozen} from "./lib/Errors.sol";
// import {ERC20_APPROVAL_SELECTOR} from "./lib/Constants.sol";
import {ApprovalType} from "./lib/Enums.sol";
import {EnumerableMap, EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";
import {
    IERC20_721_APPROVE_SELECTOR,
    IERC20_NONSTANDARD_INCREASE_ALLOWANCE_SELECTOR,
    IERC721_1155_SET_APPROVAL_FOR_ALL_SELECTOR,
    SELECTOR_MASK
} from "./lib/Constants.sol";
import {TrackedApproval, createTrackedApproval} from "./lib/types/TrackedApproval.sol";

contract Account is Clone, Executable, TokenOwnable {
    // using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public isFrozen;
    // track each type of approval for each token
    EnumerableSet.UintSet _trackedApprovals;
    // track which addresses were approved for each approval type
    mapping(uint256 => EnumerableSet.AddressSet) _trackedApprovalsToAddresses;
    // track the values of each approval for each address
    mapping(uint256 => mapping(address => EnumerableSet.UintSet)) _trackedApprovalTypesToAddressesToValues;

    function freeze() public {
        _onlyOwner();
        isFrozen = true;
    }

    function _notFrozen() internal view {
        if (isFrozen) {
            revert AccountFrozen();
        }
    }

    function _trackApprovals(address target, bytes calldata callData) internal {
        uint256 selector = _getSelector(callData);
        address approvedAddress = _getApprovedAddressFromApproveCalldata(callData);
        uint256 approvedValue = _getApprovedValueFromApproveCalldata(callData);
        TrackedApproval trackedApproval = createTrackedApproval(selector, target);
        _trackedApprovalTypes
    }

    function _getApprovedAddressFromApproveCalldata(bytes calldata callData) internal returns (address) {
        ///@solidity memory-safe-assembly
        assembly {
            let addr := calldataload(add(callData.offset, 0x24))
        }
    }

    function _getApprovedValueFromApproveCalldata(bytes calldata callData) internal returns (uint256) {
        ///@solidity memory-safe-assembly
        assembly {
            let value := calldataload(add(callData.offset, 0x44))
        }
    }

    function _getSelector(bytes calldata callData) internal pure returns (uint256 selector) {
        ///@solidity memory-safe-assembly
        assembly {
            selector := calldataload(callData.offset)
            selector := and(selector, SELECTOR_MASK)
        }
    }

    function _msgSender() internal view override (Context) returns (address msgSender) {
        if (msg.sender == address(_getTokenContract())) {
            // read address from the word before the imutableArgsOffset
            uint256 immutableArgsOffset = _getImmutableArgsOffset();
            ///@solidity memory-safe-assembly
            assembly {
                msgSender := calldataload(sub(immutableArgsOffset, 0x20))
            }
        }
        return msg.sender;
    }

    function _getTokenContract() internal pure override returns (IERC721) {
        return IERC721(_getArgAddress(0));
    }

    function _getTokenId() internal pure override returns (uint256) {
        return _getArgUint256(32);
    }

    function _onlyOwner() internal view override (TokenOwnable, Executable) {
        TokenOwnable._onlyOwner();
    }
}
