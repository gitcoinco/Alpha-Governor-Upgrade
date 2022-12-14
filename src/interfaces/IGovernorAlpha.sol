// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface IGovernorAlpha {
  event ProposalCanceled(uint256 id);
  event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
  );
  event ProposalExecuted(uint256 id);
  event ProposalQueued(uint256 id, uint256 eta);
  event VoteCast(address voter, uint256 proposalId, bool support, uint256 votes);

  struct Receipt {
    bool hasVoted;
    bool support;
    uint96 votes;
  }

  function BALLOT_TYPEHASH() external view returns (bytes32);
  function DOMAIN_TYPEHASH() external view returns (bytes32);
  function cancel(uint256 proposalId) external;
  function castVote(uint256 proposalId, bool support) external;
  function castVoteBySig(uint256 proposalId, bool support, uint8 v, bytes32 r, bytes32 s) external;
  function execute(uint256 proposalId) external payable;
  function getActions(uint256 proposalId)
    external
    view
    returns (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    );
  function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);
  function gtc() external view returns (address);
  function latestProposalIds(address) external view returns (uint256);
  function name() external view returns (string memory);
  function proposalCount() external view returns (uint256);
  function proposalMaxOperations() external pure returns (uint256);
  function proposalThreshold() external pure returns (uint256);
  function proposals(uint256)
    external
    view
    returns (
      uint256 id,
      address proposer,
      uint256 eta,
      uint256 startBlock,
      uint256 endBlock,
      uint256 forVotes,
      uint256 againstVotes,
      bool canceled,
      bool executed
    );
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
  function queue(uint256 proposalId) external;
  function quorumVotes() external pure returns (uint256);
  function state(uint256 proposalId) external view returns (uint8);
  function timelock() external view returns (address);
  function votingDelay() external pure returns (uint256);
  function votingPeriod() external pure returns (uint256);
}
