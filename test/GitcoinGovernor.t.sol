// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";
import {DeployScript} from "script/Deploy.s.sol";

contract GitcoinGovernorTest is Test {
  uint256 QUORUM = 2_500_000e18;
  address GTC_TOKEN = 0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F;
  address TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;

  uint256 INITIAL_VOTING_DELAY = 13_140;
  uint256 INITIAL_VOTING_PERIOD = 40_320;
  uint256 INITIAL_PROPOSAL_THRESHOLD = 1_000_000e18;

  GitcoinGovernor governor;

  function setUp() public {
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
