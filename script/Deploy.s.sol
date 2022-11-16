// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";

contract DeployInput {
  uint256 constant INITIAL_VOTING_DELAY = 13_140;
  uint256 constant INITIAL_VOTING_PERIOD = 40_320;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000e18;
}

contract DeployScript is DeployInput, Script {
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  }

  function run() public returns (GitcoinGovernor) {
    vm.startBroadcast(deployerPrivateKey);
    GitcoinGovernor _governor =
      new GitcoinGovernor(INITIAL_VOTING_DELAY, INITIAL_VOTING_PERIOD, INITIAL_PROPOSAL_THRESHOLD);
    vm.stopBroadcast();

    return _governor;
  }
}
