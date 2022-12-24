// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721A} from "ERC721A/ERC721A.sol";
import {Create2ClonesWithImmutableArgs} from "create2-clones-with-immutable-args/Create2ClonesWithImmutableArgs.sol";
import {Agent} from "./Agent.sol";

/**
 * @title ERC721Agent
 * @notice This ERC721 contract can deploy an Agent contract for each token to a deterministic address. That means the
 *         address of each Agent is possible to know beforehand, and thus it is possible to do things like deposit
 *         funds or tokens beforehand for its eventual owner.
 *         Anyone may deploy the Agent contract for a token, but only the token owner may execute actions on behalf of
 *         the Agent contract.
 */
contract ERC721Agent is ERC721A {
    error AgentAlreadyDeployed(uint256 tokenId, address agentAddress);
    error AgentMustBeFrozenBeforeApprovedTransfer();

    address immutable AGENT_IMPLEMENTATION;

    mapping(uint256 => address) public tokenIdToAgentAddress;

    constructor(address agentImplementation, string memory _name, string memory _symbol) ERC721A(_name, _symbol) {
        if (agentImplementation == address(0) || agentImplementation.code.length == 0) {
            agentImplementation = address(new Agent());
        }
        AGENT_IMPLEMENTATION = agentImplementation;
    }

    function mint(address to, uint256 numTokens) external virtual {
        _mint(to, numTokens);
    }

    function deployAgent(uint256 tokenId) public virtual returns (address) {
        ownerOf(tokenId); // revert if tokenId does not exist for simpler _beforeTokenTransfer logic
        if (hasAgentBeenDeployed(tokenId)) {
            revert AgentAlreadyDeployed(tokenId, tokenIdToAgentAddress[tokenId]);
        }
        address agentAddress =
            Create2ClonesWithImmutableArgs.clone(AGENT_IMPLEMENTATION, abi.encode(address(this), tokenId), bytes32(0));
        tokenIdToAgentAddress[tokenId] = agentAddress;
        return agentAddress;
    }

    function hasAgentBeenDeployed(uint256 tokenId) public view returns (bool) {
        return tokenIdToAgentAddress[tokenId] != address(0);
    }

    function deriveAgentAddress(uint256 tokenId, bytes32 salt) public pure returns (address) {
        revert("I still need to implement this function");
    }

    function _beforeTokenTransfers(address from, address, uint256 startTokenId, uint256 quantity)
        internal
        virtual
        override
    {
        if (quantity == 1 && msg.sender != from) {
            address agentAddress = tokenIdToAgentAddress[startTokenId];
            if (agentAddress != address(0) && !Agent(agentAddress).isFrozen()) {
                revert AgentMustBeFrozenBeforeApprovedTransfer();
            }
        }
    }
}
