// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GitcoinGovernor, ICompoundTimelock} from "src/GitcoinGovernor.sol";
import {DeployInput, DeployScript} from "script/Deploy.s.sol";
import {IGovernorAlpha} from "src/IGovernorAlpha.sol";
import {IGTC} from "src/IGTC.sol";
import {ProposeScript} from "script/Propose.s.sol";

contract GitcoinGovernorTest is Test, DeployInput {
  uint256 constant QUORUM = 2_500_000e18;
  address constant GTC_TOKEN = 0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F;
  address constant TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;
  address constant PROPOSER = 0xc2E2B715d9e302947Ec7e312fd2384b5a1296099; // kbw.eth

  GitcoinGovernor governor;

  function setUp() public virtual {
    uint256 _forkBlock = 15980096; // The latest block when this test was written
    vm.createSelectFork(vm.rpcUrl("mainnet"), _forkBlock);

    DeployScript _deployScript = new DeployScript();
    _deployScript.setUp();
    governor = _deployScript.run();
  }

  function testFuzz_deployment(uint256 _blockNumber) public {
    assertEq(governor.name(), "GTC Governor Bravo");
    assertEq(address(governor.token()), GTC_TOKEN);
    assertEq(governor.votingDelay(), INITIAL_VOTING_DELAY);
    assertEq(governor.votingPeriod(), INITIAL_VOTING_PERIOD);
    assertEq(governor.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);
    assertEq(governor.quorum(_blockNumber), QUORUM);
    assertEq(governor.timelock(), TIMELOCK);
    assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
  }
}

contract GitcoinGovernorProposalTest is GitcoinGovernorTest {

  IGovernorAlpha governorAlpha = IGovernorAlpha(0xDbD27635A534A3d3169Ef0498beB56Fb9c937489);
  IGTC gtcToken = IGTC(GTC_TOKEN);
  ICompoundTimelock timelock = ICompoundTimelock(payable(TIMELOCK));
  uint256 initialProposalCount;
  uint256 proposalId;
  address[] delegates = [
    PROPOSER, // kbw.eth (~1.8M)
    0x2df9a188fBE231B0DC36D14AcEb65dEFbB049479, // janineleger.eth (~1.53M)
    0x4Be88f63f919324210ea3A2cCAD4ff0734425F91, // kevinolsen.eth (~1.35M)
    0x34aA3F359A9D614239015126635CE7732c18fDF3, // Austin Griffith (~1.05M)
    0x7E052Ef7B4bB7E5A45F331128AFadB1E589deaF1, // Kris Is (~1.05M)
    0x5e349eca2dc61aBCd9dD99Ce94d04136151a09Ee // Linda Xie (~1.02M)
  ];

  // As defined in the GovernorAlpha ProposalState Enum
  uint8 constant PENDING = 0;
  uint8 constant ACTIVE = 1;
  uint8 constant DEFEATED = 3;
  uint8 constant SUCCEEDED = 4;
  uint8 constant QUEUED = 5;
  uint8 constant EXECUTED = 7;

  function setUp() public virtual override {
    super.setUp();

    initialProposalCount = governorAlpha.proposalCount();

    ProposeScript _proposeScript = new ProposeScript();
    proposalId = _proposeScript.run(governor);
  }

  //--------------- HELPERS ---------------//

  function proposalStartBlock() public view returns (uint256) {
    (,,,uint256 _startBlock,,,,,) = governorAlpha.proposals(proposalId);
    return _startBlock;
  }

  function proposalEndBlock() public view returns (uint256) {
    (,,,,uint256 _endBlock,,,,) = governorAlpha.proposals(proposalId);
    return _endBlock;
  }

  function proposalEta() public view returns (uint256) {
    (,,uint256 _eta,,,,,,) = governorAlpha.proposals(proposalId);
    return _eta;
  }

  function jumpToActiveProposal() public {
    vm.roll(proposalStartBlock() + 1);
  }

  function jumpToVoteComplete() public {
    vm.roll(proposalEndBlock() + 1);
  }

  function jumpPastProposalEta() public {
    vm.roll(block.number + 1); // move up one block so we're not in the same block as when queued
    vm.warp(proposalEta() + 1); // jump past the eta timestamp
  }

  function passProposal() public {
    jumpToActiveProposal();

    // All delegates vote in support
    for (uint _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index]);
      governorAlpha.castVote(proposalId, true);
    }

    jumpToVoteComplete();
  }

  function passAndQueueProposal() public {
    passProposal();
    governorAlpha.queue(proposalId);
  }

  //--------------- TESTS ---------------//

  function test_Proposal() public {
    // Proposal has been recorded
    assertEq(governorAlpha.proposalCount(), initialProposalCount + 1);

    // Proposal is in the expected state
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, PENDING);

    // Proposal actions correspond to Governor upgrade
    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(proposalId);
    assertEq(_targets.length, 2);
    assertEq(_targets[0], TIMELOCK);
    assertEq(_targets[1], address(governor));
    assertEq(_values.length, 2);
    assertEq(_values[0], 0);
    assertEq(_values[1], 0);
    assertEq(_signatures.length, 2);
    assertEq(_signatures[0], "setPendingAdmin(address)");
    assertEq(_signatures[1], "__acceptAdmin()");
    assertEq(_calldatas.length, 2);
    assertEq(_calldatas[0], abi.encode(address(governor)));
    assertEq(_calldatas[1], "");
  }

  function test_proposalActiveAfterDelay() public {
    jumpToActiveProposal();

    // Ensure proposal has become active the block after the voting delay
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, ACTIVE);
  }

  function testFuzz_ProposerCanCastVote(bool _willSupport) public {
    jumpToActiveProposal();
    uint256 _proposerVotes = gtcToken.getPriorVotes(PROPOSER, proposalStartBlock());

    vm.prank(PROPOSER);
    governorAlpha.castVote(proposalId, _willSupport);

    IGovernorAlpha.Receipt memory _receipt = governorAlpha.getReceipt(proposalId, PROPOSER);
    assertEq(_receipt.hasVoted, true);
    assertEq(_receipt.support, _willSupport);
    assertEq(_receipt.votes, _proposerVotes);
  }

  function test_ProposalSucceedsWhenAllDelegatesVoteFor() public {
    jumpToActiveProposal();

    // All delegates vote in support
    for (uint _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index]);
      governorAlpha.castVote(proposalId, true);
    }

    jumpToVoteComplete();

    // Ensure proposal state is now succeeded
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, SUCCEEDED);
  }

  function test_ProposalDefeatedWhenAllDelegatesVoteAgainst() public {
    jumpToActiveProposal();

    // All delegates vote against
    for (uint _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index]);
      governorAlpha.castVote(proposalId, false);
    }

    jumpToVoteComplete();

    // Ensure proposal state is now defeated
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, DEFEATED);
  }

  function test_ProposalCanBeQueuedAfterSucceeding() public {
    passProposal();
    governorAlpha.queue(proposalId);

    // Ensure proposal can be queued after success
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, QUEUED);

    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(proposalId);

    uint256 _eta = block.timestamp + timelock.delay();

    for (uint _index = 0; _index < _targets.length; _index++) {
      // Calculate hash of transaction in Timelock
      bytes32 _txHash = keccak256(
        abi.encode(_targets[_index],
        _values[_index],
        _signatures[_index],
        _calldatas[_index],
        _eta)
      );

      // Ensure transaction is queued in Timelock
      bool _isQueued = timelock.queuedTransactions(_txHash);
      assertEq(_isQueued, true);
    }
  }

  function test_ProposalCanBeExecutedAfterDelay() public {
    passAndQueueProposal();
    jumpPastProposalEta();

    // Execute the proposal
    governorAlpha.execute(proposalId);

    // Ensure the proposal is now executed
    uint8 _state = governorAlpha.state(proposalId);
    assertEq(_state, EXECUTED);

    // Ensure the governor is now the admin of the timelock
    assertEq(timelock.admin(), address(governor));
  }
}
