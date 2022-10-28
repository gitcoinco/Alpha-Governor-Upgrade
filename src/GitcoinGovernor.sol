// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

// forgefmt: disable-start
import { Governor, GovernorCountingSimple } from "openzeppelin-contracts/governance/extensions/GovernorCountingSimple.sol";
import { ERC20VotesComp, GovernorVotesComp } from "openzeppelin-contracts/governance/extensions/GovernorVotesComp.sol";
import { GovernorTimelockCompound, ICompoundTimelock } from "openzeppelin-contracts/governance/extensions/GovernorTimelockCompound.sol";
import { GovernorSettings } from "openzeppelin-contracts/governance/extensions/GovernorSettings.sol";
// forgefmt: disable-end

/// @notice The upgraded Gitcoin Governor: Bravo compatible and built with OpenZeppelin.
contract GitcoinGovernor is
  GovernorCountingSimple,
  GovernorVotesComp,
  GovernorTimelockCompound,
  GovernorSettings
{
  /// @notice The address of the GTC token on Ethereum mainnet from which this Governor derives
  /// delegated voting weight.
  ERC20VotesComp private constant GTC_TOKEN =
    ERC20VotesComp(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);

  /// @notice The address of the existing GitcoinDAO Timelock on Ethereum mainnet through which
  /// this Governor executes transactions.
  ICompoundTimelock private constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));

  /// @notice Human readable name of this Governor.
  string private constant GOVERNOR_NAME = "GTC Governor Bravo";

  /// @notice The number of GTC (in "wei") that must participate in a vote for it to meet quorum
  /// threshold.
  uint256 private constant QUORUM = 2_500_000e18; // 2,500,000 GTC

  /// @param _initialVotingDelay The deployment value for the voting delay this Governor will
  /// enforce.
  /// @param _initialVotingPeriod The deployment value for the voting period this Governor will
  /// enforce.
  /// @param _initialProposalThreshold The deployment value for the number of GTC required to submit
  /// a proposal this Governor will enforce.
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

  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override (Governor, GovernorTimelockCompound)
    returns (bool)
  {
    return GovernorTimelockCompound.supportsInterface(interfaceId);
  }

  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalThreshold()
    public
    view
    virtual
    override (Governor, GovernorSettings)
    returns (uint256)
  {
    return GovernorSettings.proposalThreshold();
  }

  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function state(uint256 proposalId)
    public
    view
    virtual
    override (Governor, GovernorTimelockCompound)
    returns (ProposalState)
  {
    return GovernorTimelockCompound.state(proposalId);
  }

  /// @notice The amount of GTC required to meet the quorum threshold for a proposal
  /// as of a given block.
  /// @dev Our implementation ignores the block number parameter and returns a constant.
  function quorum(uint256) public pure override returns (uint256) {
    return QUORUM; // TODO: should quorum be upgradeable too?
  }

  /// @dev We override this function to resolve ambiguity between inherited contracts.
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

  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override (Governor, GovernorTimelockCompound) returns (uint256) {
    return GovernorTimelockCompound._cancel(targets, values, calldatas, descriptionHash);
  }

  /// @dev We override this function to resolve ambiguity between inherited contracts.
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
