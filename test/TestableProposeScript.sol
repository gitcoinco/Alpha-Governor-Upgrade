// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {ProposeScript} from "script/Propose.s.sol";

/// @dev An extension of the proposal script for use in tests
contract TestableProposeScript is ProposeScript {
  /// @dev Used only in the context of testing in order to allow an alternate address to be the
  /// proposer. This is needed when testing with live proposal data, because the Governor only
  /// allows each proposer to have one live proposal at a time.
  function overrideProposerForTests(address _testProposer) external {
    PROPOSER = _testProposer;
  }
}
