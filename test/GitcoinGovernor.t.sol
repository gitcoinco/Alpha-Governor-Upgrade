// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";
import {DeployInput, DeployScript} from "script/Deploy.s.sol";
import {IGovernorAlpha} from "src/IGovernorAlpha.sol";
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
  uint256 initialProposalCount;
  uint256 proposalId;

  // As defined in the GovernorAlpha ProposalState Enum
  uint8 constant PENDING = 0;

  function setUp() public virtual override {
    super.setUp();

    initialProposalCount = governorAlpha.proposalCount();

    ProposeScript _proposeScript = new ProposeScript();
    proposalId = _proposeScript.run(governor);
  }

  function test_proposal() public {
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
    assertEq(_targets.length, 1);
    assertEq(_targets[0], TIMELOCK);
    assertEq(_values.length, 1);
    assertEq(_values[0], 0);
    assertEq(_signatures.length, 1);
    assertEq(_signatures[0], "setPendingAdmin(address)");
    assertEq(_calldatas.length, 1);
    assertEq(_calldatas[0], abi.encode(address(governor)));
  }
}
