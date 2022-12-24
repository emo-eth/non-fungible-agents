// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clone} from "create2-clones-with-immutable-args/Clone.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
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

contract Agent is Clone, Executable, TokenOwnable {
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

    function setApprovalForAll(address tokenAddress, address approvedAddress, bool approved) public returns (bool) {
        _onlyOwner();
        _notFrozen();
        _updateApprovedOperator(
            _approvedForAll, _approvalsForAll[tokenAddress], tokenAddress, approvedAddress, approved ? 1 : 0
        );
        IERC721(tokenAddress).setApprovalForAll(approvedAddress, approved);
    }

    function approveErc721(address tokenAddress, address approvedAddress, uint256 tokenId) public {
        _onlyOwner();
        _notFrozen();
        _updateApprovedOperator(
            _approvedErc20s, _erc20ApprovalsMap[tokenAddress], tokenAddress, approvedAddress, tokenId
        );
        // ensure it's an ERC721, since selector is same as ERC20
        require(IERC721(tokenAddress).ownerOf(tokenId) == address(this), "Account: not owner of token");
        IERC721(tokenAddress).approve(approvedAddress, tokenId);
    }

    function approveErc20(address tokenAddress, address approvedAddress, uint256 amount) public {
        _onlyOwner();
        _notFrozen();
        _updateApprovedOperator(
            _approvedErc20s, _erc20ApprovalsMap[tokenAddress], tokenAddress, approvedAddress, amount
        );

        IERC20(tokenAddress).approve(approvedAddress, amount);
        // ensure it's an ERC20, since selector is same as ERC721
        try IERC20(tokenAddress).allowance(address(this), approvedAddress) returns (uint256) {
            // do nothing
        } catch {
            revert("Not ERC20");
        }
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
        if (approvalType == ApprovalType.ERC20_APPROVE) {
            _updateApprovedOperator(_approvedErc20s, _erc20ApprovalsMap[target], target, approvedAddress, approvedValue);
        } else if (approvalType == ApprovalType.SET_APPROVAL_FOR_ALL) {
            _updateApprovedOperator(_approvedForAll, _approvalsForAll[target], target, approvedAddress, approvedValue);
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
            if (approvedValue > 0) {
                // increase allowance
                uint256 currentValue;
                if (_erc20ApprovalsMap[target].contains(approvedAddress)) {
                    currentValue = _erc20ApprovalsMap[target].get(approvedAddress);
                } else {
                    currentValue = 0;
                }
                uint256 newValue = currentValue + approvedValue;
                _updateApprovedOperator(_approvedErc20s, _erc20ApprovalsMap[target], target, approvedAddress, newValue);
            }
        }
        // TODO: track decreases
    }

    function _clearAllTokenApprovals() internal {
        uint256 length = _approvedErc20s.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedErc20s.at(0);
                _clearErc20Approvals(tokenAddress);
                _approvedErc20s.remove(tokenAddress);
            }
        }
        length = _approvedErc721s.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedErc721s.at(0);
                _clearErc721Approvals(tokenAddress);
                _approvedErc721s.remove(tokenAddress);
            }
        }
        length = _approvedForAll.length();
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                address tokenAddress = _approvedForAll.at(0);
                _clearApprovalsForAll(tokenAddress);
                _approvedForAll.remove(tokenAddress);
            }
        }
    }

    function _clearErc20Approvals(address tokenAddress) internal {
        uint256 erc20ApprovalsLength = _erc20ApprovalsMap[tokenAddress].length();
        unchecked {
            for (uint256 i = 0; i < erc20ApprovalsLength; ++i) {
                (address operator,) = _erc20ApprovalsMap[tokenAddress].at(0);

                IERC20(tokenAddress).approve(operator, 0);
                _erc20ApprovalsMap[tokenAddress].remove(operator);
                // todo: try decrease?
            }
        }
        // todo: probably unsafe
        // _erc20ApprovalsMap[tokenAddress].clear();
    }

    function _clearApprovalsForAll(address tokenAddress) internal {
        uint256 approvalsForAllLength = _approvalsForAll[tokenAddress].length();
        unchecked {
            for (uint256 i = 0; i < approvalsForAllLength; ++i) {
                (address operator,) = _approvalsForAll[tokenAddress].at(0);
                IERC721(tokenAddress).setApprovalForAll(operator, false);
                _approvalsForAll[tokenAddress].remove(operator);
            }
        }
    }

    function _clearErc721Approvals(address tokenAddress) internal {
        uint256 erc721ApprovalsLength = _erc721ApprovalsMap[tokenAddress].length();
        unchecked {
            for (uint256 i = 0; i < erc721ApprovalsLength; ++i) {
                (uint256 tokenId,) = _erc721ApprovalsMap[tokenAddress].at(0);
                IERC721(tokenAddress).approve(address(0), tokenId);
                _erc721ApprovalsMap[tokenAddress].remove(tokenId);
            }
        }
    }

    function _updateApprovedOperator(
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
