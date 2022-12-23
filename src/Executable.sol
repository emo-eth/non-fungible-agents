// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC173} from "./IERC173.sol";
import {Bundle} from "./lib/Structs.sol";

contract Executable {
    /**
     * @notice Admin function that allows the owner to execute any transaction on behalf of the contract.
     *
     * @param target The address of the contract to execute the transaction on.
     * @param value The amount of ether to send with the transaction.
     * @param data The data to send with the transaction.
     * @return The bytes returned by the transaction.
     */

    function execute(address target, uint256 value, bytes calldata data)
        public
        payable
        virtual
        returns (bytes memory)
    {
        return _execute(target, value, data);
    }

    function _execute(address target, uint256 value, bytes calldata data) internal virtual returns (bytes memory) {
        // call target, sending value ether and data as calldata
        (bool success, bytes memory returned) = target.call{value: value}(data);
        if (success) {
            // if successful, return the bytes returned by the call
            return returned;
        } else {
            // otherwise, revert with the reason provided by the call
            ///@solidity memory-safe-assembly
            assembly {
                revert(add(returned, 0x20), mload(returned))
            }
        }
    }

    function executeBundle(Bundle[] calldata bundles) public payable virtual returns (bytes[] memory) {
        // allocate memory for the results
        bytes[] memory results = new bytes[](bundles.length);
        // execute each bundle
        unchecked {
            for (uint256 i = 0; i < bundles.length; ++i) {
                Bundle calldata bundle = bundles[i];
                results[i] = _execute(bundle.target, bundle.value, bundle.data);
            }
        }
        // return the results
        return results;
    }

    function executeOptimized(address target, uint256 value, bytes calldata data) public payable virtual {
        _executeOptimized(target, value, data);
    }

    function executeBundleOptimized(Bundle[] calldata bundles) public payable virtual {
        unchecked {
            for (uint256 i = 0; i < bundles.length; ++i) {
                Bundle calldata bundle = bundles[i];
                _executeOptimized(bundle.target, bundle.value, bundle.data);
            }
        }
    }

    function _executeOptimized(address target, uint256 value, bytes calldata data) internal {
        assembly {
            // always use 0x80 as mem pointer
            let ptr := 0x80
            // get length of data bytes
            let dataSize := data.length
            // copy data bytes (minus length) to memory
            calldatacopy(ptr, data.offset, dataSize)
            // call target, sending value ether and data as calldata
            let success := call(gas(), target, value, ptr, dataSize, 0, 0)
            if iszero(success) {
                // if the call failed, revert with the reason provided by the call
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}
