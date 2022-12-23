// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clone} from "create2-clones-with-immutable-args/Clone.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {Executable} from "./Executable.sol";
import {TokenOwnable} from "./TokenOwnable.sol";
import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";
import {AccountFrozen, UseApprovalSpecificMethods} from "./lib/Errors.sol";
// import {ERC20_APPROVAL_SELECTOR} from "./lib/Constants.sol";
import {TokenType, ApprovalType} from "./lib/Enums.sol";
import {EnumerableMap, EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";
import {
    IERC20_721_APPROVE_SELECTOR,
    IERC20_NONSTANDARD_INCREASE_ALLOWANCE_SELECTOR,
    IERC721_1155_SET_APPROVAL_FOR_ALL_SELECTOR,
    SELECTOR_MASK
} from "./lib/Constants.sol";
import {TrackedApproval, createTrackedApproval} from "./lib/types/TrackedApproval.sol";
import {Bundle} from "./lib/Structs.sol";

contract Account is Clone, Executable, TokenOwnable {
    // using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    bool public isFrozen;

    EnumerableSet.AddressSet _approvedErc20s;
    EnumerableSet.AddressSet _approvedErc721s;
    EnumerableSet.AddressSet _approvedForAll;

    mapping(address => EnumerableMap.AddressToUintMap) _approvalsForAll;
    mapping(address => EnumerableMap.AddressToUintMap) _erc20ApprovalsMap;
    mapping(address => EnumerableMap.UintToAddressMap) _erc721ApprovalsMap;

    function freeze() public {
        _onlyOwner();
        isFrozen = true;
    }

    function execute(address target, uint256 value, bytes calldata callData)
        public
        payable
        override
        returns (bytes memory)
    {
        _onlyOwner();
        _notFrozen();
        _notApproval(callData);
        return super.execute(target, value, callData);
    }

    function executeBundle(Bundle[] calldata bundles) public payable override returns (bytes[] memory) {
        _onlyOwner();
        _notFrozen();
        unchecked {
            for (uint256 i = 0; i < bundles.length; ++i) {
                _notApproval(bundles[i].data);
            }
        }
        return super.executeBundle(bundles);
    }

    function executeOptimized(address target, uint256 value, bytes calldata callData) public payable override {
        _onlyOwner();
        _notFrozen();
        _notApproval(callData);
        return super.executeOptimized(target, value, callData);
    }

    function executeBundleOptimized(Bundle[] calldata bundles) public payable override {
        _onlyOwner();
        _notFrozen();
        unchecked {
            for (uint256 i = 0; i < bundles.length; ++i) {
                _notApproval(bundles[i].data);
            }
        }
        return super.executeBundleOptimized(bundles);
    }

    function _notFrozen() internal view {
        if (isFrozen) {
            revert AccountFrozen();
        }
    }

    function _notApproval(bytes calldata callData) internal pure {
        if (_isApproval(callData)) {
            revert UseApprovalSpecificMethods();
        }
    }

    function _isApproval(bytes calldata callData) internal pure returns (bool) {
        uint256 selector = _getSelector(callData);
        return selector == IERC20_721_APPROVE_SELECTOR || selector == IERC20_NONSTANDARD_INCREASE_ALLOWANCE_SELECTOR
            || selector == IERC721_1155_SET_APPROVAL_FOR_ALL_SELECTOR;
    }

    function _trackApprovals(ApprovalType approvalType, address target, address approvedAddress, uint256 approvedValue)
        internal
    {
        // TrackedApproval trackedApproval = createTrackedApproval(selector, target);

        if (approvalType == ApprovalType.ERC20_APPROVE) {
            updateApprovedOperator(_approvedErc20s, _erc20ApprovalsMap[target], target, approvedAddress, approvedValue);
        } else if (approvalType == ApprovalType.SET_APPROVAL_FOR_ALL) {
            updateApprovedOperator(_approvedForAll, _approvalsForAll[target], target, approvedAddress, approvedValue);
        } else if (approvalType == ApprovalType.ERC721_APPROVE) {
            if (approvedAddress == address(0)) {
                bool removed = _erc721ApprovalsMap[target].remove(approvedValue);
                if (removed && _erc721ApprovalsMap[target].length() == 0) {
                    _approvedErc721s.remove(target);
                }
            } else {
                _approvedErc721s.add(target);
                _erc721ApprovalsMap[target].set(approvedValue, approvedAddress);
            }
        } else {
            // increase allowance
            uint256 currentValue = _erc20ApprovalsMap[target].get(approvedAddress);
            uint256 newValue = currentValue + approvedValue;
            updateApprovedOperator(_approvedErc20s, _erc20ApprovalsMap[target], target, approvedAddress, newValue);
        }
    }

    function _clearTokenApprovals() internal {
        uint256 length = _approvedErc20s.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedErc20s.at(0);
                _clearTokenApproval(TokenType.ERC20, ApprovalType.ERC20_APPROVE, tokenAddress);
                _approvedErc20s.remove(tokenAddress);
            }
        }
        length = _approvedErc721s.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedErc721s.at(0);
                _clearTokenApproval(TokenType.ERC721, ApprovalType.ERC721_APPROVE, tokenAddress);
                _approvedErc721s.remove(tokenAddress);
            }
        }
        length = _approvedForAll.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedForAll.at(0);
                _clearTokenApproval(TokenType.ERC1155, ApprovalType.SET_APPROVAL_FOR_ALL, tokenAddress);
                _approvedForAll.remove(tokenAddress);
            }
        }
    }

    function _clearTokenApproval(TokenType tokenType, ApprovalType approvalType, address tokenAddress) internal {}

    function updateApprovedOperator(
        EnumerableSet.AddressSet storage toUpdate,
        EnumerableMap.AddressToUintMap storage toAddOrRemove,
        address target,
        address operator,
        uint256 value
    ) internal {
        if (value == 0) {
            _removeAndUpdateTracked(toUpdate, toAddOrRemove, operator);
        } else {
            toUpdate.add(target);
            toAddOrRemove.set(operator, value);
        }
    }

    function _removeAndUpdateTracked(
        EnumerableSet.AddressSet storage toUpdate,
        EnumerableMap.AddressToUintMap storage toRemove,
        address target
    ) internal {
        bool removed = toRemove.remove(target);
        if (removed && toRemove.length() == 0) {
            toUpdate.remove(target);
        }
    }

    function _getApprovedAddressFromApproveCalldata(bytes calldata callData) internal pure returns (address addr) {
        ///@solidity memory-safe-assembly
        assembly {
            addr := calldataload(add(callData.offset, 0x24))
        }
    }

    function _getApprovedValueFromApproveCalldata(bytes calldata callData) internal pure returns (uint256 value) {
        ///@solidity memory-safe-assembly
        assembly {
            value := calldataload(add(callData.offset, 0x44))
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
}
