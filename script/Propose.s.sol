// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {GitcoinGovernor} from "src/GitcoinGovernor.sol";
import {IGovernorAlpha} from "src/IGovernorAlpha.sol";
import {ICompoundTimelock} from "openzeppelin-contracts/governance/extensions/GovernorTimelockCompound.sol";

contract ProposeScript is Script {
  IGovernorAlpha constant governorAlpha = IGovernorAlpha(0xDbD27635A534A3d3169Ef0498beB56Fb9c937489);
  address constant proposer = 0xc2E2B715d9e302947Ec7e312fd2384b5a1296099; // kbw.eth

  function propose(GitcoinGovernor _newGovernor) internal returns (uint256 _proposalId) {
    address[] memory _targets = new address[](2);
    uint256[] memory _values = new uint256[](2);
    string[] memory _signatures = new string [](2);
    bytes[] memory _calldatas = new bytes[](2);

    _targets[0] = governorAlpha.timelock();
    _values[0] = 0;
    _signatures[0] = "setPendingAdmin(address)";
    _calldatas[0] = abi.encode(address(_newGovernor));

    _targets[1] = address(_newGovernor);
    _values[1] = 0;
    _signatures[1] = "__acceptAdmin()";
    _calldatas[1] = "";

    return governorAlpha.propose(
        _targets,
        _values,
        _signatures,
        _calldatas,
        "Upgrade to Governor Bravo"
    );
  }

  /// @dev After the new Governor is deployed on mainnet, this can move from a parameter to a const
  function run(GitcoinGovernor _newGovernor) public returns (uint256 _proposalId) {
    // The expectation is the key loaded here corresponds to the address of the `proposer` above.
    // When running as a script, broadcast will fail if the key is not correct.
    uint256 _proposerKey = vm.envUint("PROPOSER_PRIVATE_KEY");
    vm.rememberKey(_proposerKey);

    vm.startBroadcast(proposer);
    _proposalId = propose(_newGovernor);
    vm.stopBroadcast();
  }
}
