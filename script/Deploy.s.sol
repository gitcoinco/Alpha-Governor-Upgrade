// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";

contract DeployScript is Script, Test {
  struct DeployInputData {
    // must be in alphabetical order to parse correctly
    uint256 initialProposalThreshold;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
  }
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  }

  function readInput() public returns (DeployInputData memory) {
    string memory _read = vm.readFile("./script/deploy-input.json");
    bytes memory _data = vm.parseJson(_read);
    DeployInputData memory _inputs = abi.decode(_data, (DeployInputData));
    return _inputs;
  }

  function run() public returns (GitcoinGovernor) {
    // PROBLEM: Parsing fails because initialProposalThreshold exceeds uint64 max
    DeployInputData memory _inputs = readInput();

    vm.startBroadcast(deployerPrivateKey);
    GitcoinGovernor _governor =
      new GitcoinGovernor(
        _inputs.initialVotingDelay,
        _inputs.initialVotingPeriod,
        _inputs.initialProposalThreshold
      );
    vm.stopBroadcast();

    return _governor;
  }
}
