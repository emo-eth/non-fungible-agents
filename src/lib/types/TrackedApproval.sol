// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ApprovalType} from "../Enums.sol";
import {SELECTOR_MASK} from "../Constants.sol";

type TrackedApproval is uint256;

uint256 constant APPROVAL_SHIFT = 224;

function createTrackedApproval(uint256 approvalSelector, address approvedToken)
    pure
    returns (TrackedApproval trackedApproval)
{
    ///@solidity memory-safe-assembly
    assembly {
        trackedApproval :=
            or( // combine the selector in the first 32 bits with the approvedToken in the last 160 bits
                and( // the selector should have already been masked, but mask again just in case
                    approvalSelector, // first word of calldata
                    SELECTOR_MASK // mask for the first 32 bits
                ),
                approvedToken // address of the approved token
            )
    }
}
