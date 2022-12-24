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

    ///@dev we use the implementation contract to create lightweight Clone proxies for each Agent, which are much
    /// cheaper to deploy
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

    /**
     * @notice Deploy an Agent contract for a token to a deterministic address, using a zero salt. Anyone may call
     *         this function once the token has been minted, but only the token owner may execute actions on behalf of
     *         the Agent contract.
     */
    function deployAgent(uint256 tokenId) public virtual returns (address) {
        ownerOf(tokenId); // revert if tokenId does not exist, for simpler _beforeTokenTransfer logic
        return _deployAgent(tokenId, bytes32(0));
    }

    function _deployAgent(uint256 tokenId, bytes32 salt) internal virtual returns (address) {
        if (hasAgentBeenDeployed(tokenId)) {
            revert AgentAlreadyDeployed(tokenId, tokenIdToAgentAddress[tokenId]);
        }
        // create2 a lightweight clone of the Agent contract that will pass this contract's address and associated
        // tokenId as gas-efficient immutable variables in calldata.
        address agentAddress =
            Create2ClonesWithImmutableArgs.clone(AGENT_IMPLEMENTATION, abi.encode(address(this), tokenId), salt);
        tokenIdToAgentAddress[tokenId] = agentAddress;
        return agentAddress;
    }

    function hasAgentBeenDeployed(uint256 tokenId) public view returns (bool) {
        return tokenIdToAgentAddress[tokenId] != address(0);
    }

    function deriveAgentAddress(uint256 tokenId, bytes32 salt) public pure returns (address) {
        revert("I still need to implement this function");
    }

    /**
     * @notice To prevent malicious owners front-running the sale of their tokens (and thus associated Agents), eg,
     *         withdrawing funds from their Agent contract as a sale is in-flight, we require that the Agent contract
     *         be frozen before the token can be transferred to a new owner if the current
     *         owner is not the operator.
     */
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
