// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Create2ClonesWithImmutableArgs} from "create2-clones-with-immutable-args/Create2ClonesWithImmutableArgs.sol";
import {Agent} from "./Agent.sol";
import {ERC721Agent} from "./ERC721Agent.sol";

/**
 * @title ERC721_007
 * @notice This ERC721 contract can deploy an Agent contract for each token to a deterministic address, using a salt provided
 *         by the token owner. That means the owner of a token may choose to keep the Agent's deterministic address secret
 *         before eventually deploying it.
 */
contract ERC721_007 is ERC721Agent {
    error OnlyTokenOwner();

    constructor(address agentImplementation, string memory _name, string memory _symbol)
        ERC721Agent(agentImplementation, _name, _symbol)
    {}

    /**
     * @notice Revert if the caller does not own the token, or if it has not been minted yet.
     */
    function _onlyTokenOwner(uint256 tokenId) internal view {
        if (ownerOf(tokenId) != msg.sender) {
            revert OnlyTokenOwner();
        }
    }

    /**
     * @notice Deploy an Agent contract for a token to a deterministic address, using a zero salt.
     *         The caller must own the token.
     */
    function deployAgent(uint256 tokenId) public virtual override returns (address) {
        return deployAgent(tokenId, bytes32(uint256(0)));
    }

    /**
     * @notice Deploy an Agent contract for a token to a deterministic address, using a salt provided by the caller.
     *         This allows for deploying to an unpredictable (to those who do not know the salt beforehand)
     *         deterministic address.
     *         The caller must own the token.
     */
    function deployAgent(uint256 tokenId, bytes32 salt) public virtual returns (address) {
        _onlyTokenOwner(tokenId);
        if (hasAgentBeenDeployed(tokenId)) {
            revert AgentAlreadyDeployed(tokenId, tokenIdToAgentAddress[tokenId]);
        }
        // salt should depend on both tokenId and salt to avoid collision
        bytes32 compoundSalt;
        ///@solidity memory-safe-assembly
        assembly {
            mstore(0, tokenId)
            mstore(0x20, salt)
            compoundSalt := keccak256(0, 0x40)
        }
        address agentAddress =
            Create2ClonesWithImmutableArgs.clone(AGENT_IMPLEMENTATION, abi.encode(address(this), tokenId), compoundSalt);
        tokenIdToAgentAddress[tokenId] = agentAddress;
        return agentAddress;
    }
}
