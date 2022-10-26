// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {
  GovernorCountingSimple,
  Governor
} from "openzeppelin-contracts/governance/extensions/GovernorCountingSimple.sol";

import {
  GovernorVotesComp,
  ERC20VotesComp
} from "openzeppelin-contracts/governance/extensions/GovernorVotesComp.sol";

import {
  GovernorTimelockCompound,
  ICompoundTimelock
} from "openzeppelin-contracts/governance/extensions/GovernorTimelockCompound.sol";

import {GovernorSettings} from "openzeppelin-contracts/governance/extensions/GovernorSettings.sol";

contract GitcoinGovernor is
  GovernorCountingSimple,
  GovernorVotesComp,
  GovernorTimelockCompound,
  GovernorSettings
{
  ERC20VotesComp private constant GTC_TOKEN =
    ERC20VotesComp(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
  ICompoundTimelock private constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));
  string private constant GOVERNOR_NAME = "GTC Governor Bravo";
  uint256 private constant QUORUM = 2_500_000_000_000_000_000_000_000; // 2,500,000 GTC

  constructor(
    uint256 _initialVotingDelay,
    uint256 _initialVotingPeriod,
    uint256 _initialProposalThreshold
  )
    GovernorVotesComp(GTC_TOKEN)
    GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
    GovernorTimelockCompound(TIMELOCK)
    Governor(GOVERNOR_NAME)
  {}

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override (Governor, GovernorTimelockCompound)
    returns (bool)
  {
    return GovernorTimelockCompound.supportsInterface(interfaceId);
  }

  function quorum(uint256) public pure override returns (uint256) {
    return QUORUM; // TBD: should quorum be upgradeable too?
  }

  function proposalThreshold()
    public
    view
    virtual
    override (Governor, GovernorSettings)
    returns (uint256)
  {
    return GovernorSettings.proposalThreshold();
  }

  function state(uint256 proposalId)
    public
    view
    virtual
    override (Governor, GovernorTimelockCompound)
    returns (ProposalState)
  {
    return GovernorTimelockCompound.state(proposalId);
  }

  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override (Governor, GovernorTimelockCompound) {
    return GovernorTimelockCompound._execute(
      proposalId, targets, values, calldatas, descriptionHash
    );
  }

  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override (Governor, GovernorTimelockCompound) returns (uint256) {
    return GovernorTimelockCompound._cancel(targets, values, calldatas, descriptionHash);
  }

  function _executor()
    internal
    view
    virtual
    override (Governor, GovernorTimelockCompound)
    returns (address)
  {
    return GovernorTimelockCompound._executor();
  }
}
