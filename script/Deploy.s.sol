// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {DeployInput} from "script/DeployInput.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";

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
