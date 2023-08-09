// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {GitcoinGovernor, ICompoundTimelock} from "src/GitcoinGovernor.sol";
import {DeployInput, DeployScript} from "script/Deploy.s.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {IGTC} from "src/interfaces/IGTC.sol";
import {ProposeScript} from "script/Propose.s.sol";

abstract contract GitcoinGovernorTestHelper is Test, DeployInput {
  using FixedPointMathLib for uint256;

  uint256 constant QUORUM = 2_500_000e18;
  address constant GTC_TOKEN = 0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F;
  IGTC gtcToken = IGTC(GTC_TOKEN);
  address constant TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;
  address constant PROPOSER = 0xc2E2B715d9e302947Ec7e312fd2384b5a1296099; // kbw.eth
  address constant DEPLOYED_BRAVO_GOVERNOR = 0x9D4C63565D5618310271bF3F3c01b2954C1D1639;
  uint256 constant MAX_REASONABLE_TIME_PERIOD = 302_400; // 6 weeks assuming a 12 second block time

  struct Delegate {
    string handle;
    address addr;
    uint96 votes;
  }

  Delegate[] delegates;

  GitcoinGovernor governorBravo;

  function setUp() public virtual {
    // The latest block when this test was written. If you update the fork block
    // make sure to also update the top 6 delegates below.
    uint256 _forkBlock = 17_878_409;
    vm.createSelectFork(vm.rpcUrl("mainnet"), _forkBlock);

    // Taken from https://www.tally.xyz/gov/gitcoin/delegates?sort=voting_power_desc.
    // If you update these delegates (including updating order in the array),
    // make sure to update any tests that reference specific delegates.
    Delegate[] memory _delegates = new Delegate[](6);
    _delegates[0] = Delegate("kevinolsen.eth", 0x4Be88f63f919324210ea3A2cCAD4ff0734425F91, 1.8e6);
    _delegates[1] = Delegate("janineleger.eth", 0x2df9a188fBE231B0DC36D14AcEb65dEFbB049479, 1.7e6);
    _delegates[2] = Delegate("kbw.eth", PROPOSER, 1.2e6);
    _delegates[3] = Delegate("griff.eth", 0x839395e20bbB182fa440d08F850E6c7A8f6F0780, 0.8e6);
    _delegates[4] = Delegate("lefteris.eth", 0x2B888954421b424C5D3D9Ce9bB67c9bD47537d12, 0.6e6);
    _delegates[5] = Delegate("anon gnosis safe", 0x93F80a67FdFDF9DaF1aee5276Db95c8761cc8561, 0.5e6);

    // Fetch up-to-date voting weight for the top delegates.
    for (uint256 i; i < _delegates.length; i++) {
      Delegate memory _delegate = _delegates[i];
      _delegate.votes = gtcToken.getCurrentVotes(_delegate.addr);
      delegates.push(_delegate);
    }

    if (_useDeployedGovernorBravo()) {
      // The GitcoinGovernor contract was deployed to mainnet on April 7th 2023
      // using DeployScript in this repo.
      governorBravo = GitcoinGovernor(payable(DEPLOYED_BRAVO_GOVERNOR));
    } else {
      // We still want to exercise the script in these tests to give us
      // confidence that we could deploy again if necessary.
      DeployScript _deployScript = new DeployScript();
      _deployScript.setUp();
      governorBravo = _deployScript.run();
    }
  }

  function _useDeployedGovernorBravo() internal virtual returns (bool);
}

abstract contract BravoGovernorDeployTest is GitcoinGovernorTestHelper {
  function testFuzz_deployment(uint256 _blockNumber) public {
    assertEq(governorBravo.name(), "GTC Governor Bravo");
    assertEq(address(governorBravo.token()), GTC_TOKEN);
    // forgefmt: disable-start
    // These values were all copied directly from the mainnet alpha governor at:
    //   0xDbD27635A534A3d3169Ef0498beB56Fb9c937489
    assertEq(INITIAL_VOTING_DELAY, 13140);
    assertEq(INITIAL_VOTING_PERIOD, 40_320);
    assertEq(INITIAL_PROPOSAL_THRESHOLD, 1_000_000e18);
    // forgefmt: disable-end
    assertEq(governorBravo.votingDelay(), INITIAL_VOTING_DELAY);
    assertLt(governorBravo.votingDelay(), MAX_REASONABLE_TIME_PERIOD);
    assertEq(governorBravo.votingPeriod(), INITIAL_VOTING_PERIOD);
    assertLt(governorBravo.votingPeriod(), MAX_REASONABLE_TIME_PERIOD);
    assertEq(governorBravo.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);
    assertEq(governorBravo.quorum(_blockNumber), QUORUM);
    assertEq(governorBravo.timelock(), TIMELOCK);
    assertEq(governorBravo.COUNTING_MODE(), "support=bravo&quorum=for,abstain&params=fractional");
  }
}

abstract contract ProposalTestHelper is GitcoinGovernorTestHelper {
  //----------------- State and Setup ----------- //

  IGovernorAlpha governorAlpha = IGovernorAlpha(0xDbD27635A534A3d3169Ef0498beB56Fb9c937489);
  address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address constant RAD_ADDRESS = 0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3;
  IERC20 usdcToken = IERC20(USDC_ADDRESS);
  IERC20 radToken = IERC20(RAD_ADDRESS);
  ICompoundTimelock timelock = ICompoundTimelock(payable(TIMELOCK));
  uint256 initialProposalCount;
  uint256 upgradeProposalId;

  // As defined in the GovernorAlpha ProposalState Enum
  uint8 constant PENDING = 0;
  uint8 constant ACTIVE = 1;
  uint8 constant DEFEATED = 3;
  uint8 constant SUCCEEDED = 4;
  uint8 constant QUEUED = 5;
  uint8 constant EXECUTED = 7;

  function setUp() public virtual override {
    GitcoinGovernorTestHelper.setUp();

    if (_useDeployedGovernorBravo()) {
      // The actual upgrade proposal submitted to Governor Alpha by kbw.eth on 8/9/2023
      upgradeProposalId = 65;
      // Since the proposal was already submitted, the count before its submissions is one less
      initialProposalCount = governorAlpha.proposalCount() - 1;
    } else {
      initialProposalCount = governorAlpha.proposalCount();
      ProposeScript _proposeScript = new ProposeScript();
      // We override the deployer to use kevinolsen.eth, because in this context, kbw.eth already
      // has a live proposal
      _proposeScript.overrideProposerForTests(0x4Be88f63f919324210ea3A2cCAD4ff0734425F91);
      upgradeProposalId = _proposeScript.run(governorBravo);
    }
  }

  //--------------- HELPERS ---------------//

  function _assumeReceiver(address _receiver) internal {
    assumePayable(_receiver);
    vm.assume(
      // We don't want the receiver to be the Timelock, as that would make our
      // assertions less meaningful -- most of our tests want to confirm that
      // proposals can cause tokens to be sent *from* the timelock to somewhere
      // else.
      _receiver != TIMELOCK
      // We also can't have the receiver be the zero address because GTC
      // blocks transfers to the zero address -- see line 546:
      // https://etherscan.io/address/0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F#code
      && _receiver > address(0)
    );
    assumeNoPrecompiles(_receiver);
  }

  function _randomERC20Token(uint256 _seed) internal view returns (IERC20 _token) {
    if (_seed % 3 == 0) _token = IERC20(address(gtcToken));
    if (_seed % 3 == 1) _token = usdcToken;
    if (_seed % 3 == 2) _token = radToken;
  }

  function _upgradeProposalStartBlock() internal view returns (uint256) {
    (,,, uint256 _startBlock,,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _startBlock;
  }

  function _upgradeProposalEndBlock() internal view returns (uint256) {
    (,,,, uint256 _endBlock,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _endBlock;
  }

  function _upgradeProposalEta() internal view returns (uint256) {
    (,, uint256 _eta,,,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _eta;
  }

  function _jumpToActiveUpgradeProposal() internal {
    vm.roll(_upgradeProposalStartBlock() + 1);
  }

  function _jumpToUpgradeVoteComplete() internal {
    vm.roll(_upgradeProposalEndBlock() + 1);
  }

  function _jumpPastProposalEta() internal {
    vm.roll(block.number + 1); // move up one block so we're not in the same block as when queued
    vm.warp(_upgradeProposalEta() + 1); // jump past the eta timestamp
  }

  function _delegatesVoteOnUpgradeProposal(bool _support) internal {
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(upgradeProposalId, _support);
    }
  }

  function _passUpgradeProposal() internal {
    _jumpToActiveUpgradeProposal();
    _delegatesVoteOnUpgradeProposal(true);
    _jumpToUpgradeVoteComplete();
  }

  function _defeatUpgradeProposal() internal {
    _jumpToActiveUpgradeProposal();
    _delegatesVoteOnUpgradeProposal(false);
    _jumpToUpgradeVoteComplete();
  }

  function _passAndQueueUpgradeProposal() internal {
    _passUpgradeProposal();
    governorAlpha.queue(upgradeProposalId);
  }

  function _upgradeToBravoGovernor() internal {
    _passAndQueueUpgradeProposal();
    _jumpPastProposalEta();
    governorAlpha.execute(upgradeProposalId);
  }
}

abstract contract AlphaGovernorPreProposalTest is ProposalTestHelper {
  function test_Proposal() public {
    // Proposal has been recorded
    assertEq(governorAlpha.proposalCount(), initialProposalCount + 1);

    // Proposal is in the expected state
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, PENDING);

    // Proposal actions correspond to Governor upgrade
    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(upgradeProposalId);
    assertEq(_targets.length, 2);
    assertEq(_targets[0], TIMELOCK);
    assertEq(_targets[1], address(governorBravo));
    assertEq(_values.length, 2);
    assertEq(_values[0], 0);
    assertEq(_values[1], 0);
    assertEq(_signatures.length, 2);
    assertEq(_signatures[0], "setPendingAdmin(address)");
    assertEq(_signatures[1], "__acceptAdmin()");
    assertEq(_calldatas.length, 2);
    assertEq(_calldatas[0], abi.encode(address(governorBravo)));
    assertEq(_calldatas[1], "");
  }

  function test_proposalActiveAfterDelay() public {
    _jumpToActiveUpgradeProposal();

    // Ensure proposal has become active the block after the voting delay
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, ACTIVE);
  }

  function testFuzz_ProposerCanCastVote(bool _willSupport) public {
    _jumpToActiveUpgradeProposal();
    uint256 _proposerVotes = gtcToken.getPriorVotes(PROPOSER, _upgradeProposalStartBlock());

    vm.prank(PROPOSER);
    governorAlpha.castVote(upgradeProposalId, _willSupport);

    IGovernorAlpha.Receipt memory _receipt = governorAlpha.getReceipt(upgradeProposalId, PROPOSER);
    assertEq(_receipt.hasVoted, true);
    assertEq(_receipt.support, _willSupport);
    assertEq(_receipt.votes, _proposerVotes);
  }

  function test_ProposalSucceedsWhenAllDelegatesVoteFor() public {
    _passUpgradeProposal();

    // Ensure proposal state is now succeeded
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, SUCCEEDED);
  }

  function test_ProposalDefeatedWhenAllDelegatesVoteAgainst() public {
    _defeatUpgradeProposal();

    // Ensure proposal state is now defeated
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, DEFEATED);
  }

  function test_ProposalCanBeQueuedAfterSucceeding() public {
    _passUpgradeProposal();
    governorAlpha.queue(upgradeProposalId);

    // Ensure proposal can be queued after success
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, QUEUED);

    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(upgradeProposalId);

    uint256 _eta = block.timestamp + timelock.delay();

    for (uint256 _index = 0; _index < _targets.length; _index++) {
      // Calculate hash of transaction in Timelock
      bytes32 _txHash = keccak256(
        abi.encode(_targets[_index], _values[_index], _signatures[_index], _calldatas[_index], _eta)
      );

      // Ensure transaction is queued in Timelock
      bool _isQueued = timelock.queuedTransactions(_txHash);
      assertEq(_isQueued, true);
    }
  }

  function test_ProposalCanBeExecutedAfterDelay() public {
    _passAndQueueUpgradeProposal();
    _jumpPastProposalEta();

    // Execute the proposal
    governorAlpha.execute(upgradeProposalId);

    // Ensure the proposal is now executed
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, EXECUTED);

    // Ensure the governorBravo is now the admin of the timelock
    assertEq(timelock.admin(), address(governorBravo));
  }
}

abstract contract AlphaGovernorPostProposalTest is ProposalTestHelper {
  function _queueAndVoteAndExecuteProposalWithAlphaGovernor(
    address[] memory _targets,
    uint256[] memory _values,
    string[] memory _signatures,
    bytes[] memory _calldatas,
    bool isGovernorAlphaAdmin
  ) internal {
    // Submit the new proposal
    vm.prank(0x4Be88f63f919324210ea3A2cCAD4ff0734425F91);
    uint256 _newProposalId =
      governorAlpha.propose(_targets, _values, _signatures, _calldatas, "Proposal for old Governor");

    // Pass and execute the new proposal
    (,,, uint256 _startBlock, uint256 _endBlock,,,,) = governorAlpha.proposals(_newProposalId);
    vm.roll(_startBlock + 1);
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(_newProposalId, true);
    }
    vm.roll(_endBlock + 1);

    if (!isGovernorAlphaAdmin) {
      vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
      governorAlpha.queue(_newProposalId);
      return;
    }

    governorAlpha.queue(_newProposalId);
    vm.roll(block.number + 1);
    (,, uint256 _eta,,,,,,) = governorAlpha.proposals(_newProposalId);
    vm.warp(_eta + 1);

    governorAlpha.execute(_newProposalId);

    // Ensure the new proposal is now executed
    assertEq(governorAlpha.state(_newProposalId), EXECUTED);
  }

  function testFuzz_OldGovernorSendsETHAfterProposalIsDefeated(uint128 _amount, address _receiver)
    public
  {
    _assumeReceiver(_receiver);

    // Counter-intuitively, the Governor (not the Timelock) must hold the ETH.
    // See the deployed GovernorAlpha, line 227:
    //   https://etherscan.io/address/0xDbD27635A534A3d3169Ef0498beB56Fb9c937489#code
    // The governor transfers ETH to the Timelock in the process of executing
    // the proposal. The Timelock then just passes that ETH along.
    vm.deal(address(governorAlpha), _amount);

    uint256 _receiverETHBalance = _receiver.balance;
    uint256 _governorETHBalance = address(governorAlpha).balance;

    // Defeat the proposal to upgrade the Governor
    _defeatUpgradeProposal();

    // Create a new proposal to send the ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      new string[](1), // No signature needed for an ETH send.
      new bytes[](1), // No calldata needed for an ETH send.
      true // GovernorAlpha is still the Timelock admin.
    );

    // Ensure the ETH has been transferred to the receiver
    assertEq(address(governorAlpha).balance, _governorETHBalance - _amount);
    assertEq(_receiver.balance, _receiverETHBalance + _amount);
  }

  function testFuzz_OldGovernorCannotSendETHAfterProposalSucceeds(
    uint256 _amount,
    address _receiver
  ) public {
    _assumeReceiver(_receiver);

    // Counter-intuitively, the Governor must hold the ETH, not the Timelock.
    // See the deployed GovernorAlpha, line 227:
    //   https://etherscan.io/address/0xDbD27635A534A3d3169Ef0498beB56Fb9c937489#code
    // The governor transfers ETH to the Timelock in the process of executing
    // the proposal. The Timelock then just passes that ETH along.
    vm.deal(address(governorAlpha), _amount);

    uint256 _receiverETHBalance = _receiver.balance;
    uint256 _governorETHBalance = address(governorAlpha).balance;

    // Pass and execute the proposal to upgrade the Governor
    _upgradeToBravoGovernor();

    // Create a new proposal to send the ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      new string[](1), // No signature needed for an ETH send.
      new bytes[](1), // No calldata needed for an ETH send.
      false // GovernorAlpha is not the Timelock admin.
    );

    // Ensure no ETH has been transferred to the receiver
    assertEq(address(governorAlpha).balance, _governorETHBalance);
    assertEq(_receiver.balance, _receiverETHBalance);
  }

  function testFuzz_OldGovernorSendsTokenAfterProposalIsDefeated(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    _assumeReceiver(_receiver);
    IERC20 _token = _randomERC20Token(_seed);

    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    // Defeat the proposal to upgrade the Governor
    _defeatUpgradeProposal();

    // Craft a new proposal to send the token.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    string[] memory _signatures = new string [](1);
    bytes[] memory _calldatas = new bytes[](1);

    _targets[0] = address(_token);
    _values[0] = 0;
    _signatures[0] = "transfer(address,uint256)";
    _calldatas[0] = abi.encode(_receiver, _amount);

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      _signatures,
      _calldatas,
      true // GovernorAlpha is still the Timelock admin.
    );

    // Ensure the tokens have been transferred from the timelock to the receiver.
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amount);
    assertEq(_token.balanceOf(_receiver), _receiverTokenBalance + _amount);
  }

  function testFuzz_OldGovernorCanNotSendTokensAfterUpgradeCompletes(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    _assumeReceiver(_receiver);
    IERC20 _token = _randomERC20Token(_seed);

    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    // Pass and execute the proposal to upgrade the Governor
    _upgradeToBravoGovernor();

    // Craft a new proposal to send the token.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    string[] memory _signatures = new string [](1);
    bytes[] memory _calldatas = new bytes[](1);

    _targets[0] = address(_token);
    _values[0] = 0;
    _signatures[0] = "transfer(address,uint256)";
    _calldatas[0] = abi.encode(_receiver, _amount);

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      _signatures,
      _calldatas,
      false // GovernorAlpha is not the Timelock admin anymore.
    );

    // Ensure no tokens have been transferred from the timelock to the receiver.
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance);
    assertEq(_token.balanceOf(_receiver), _receiverTokenBalance);
  }
}

abstract contract GovernorBravoProposalHelper is ProposalTestHelper {
  // From GovernorCountingSimple
  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;

  function _buildProposalData(string memory _signature, bytes memory _calldata)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodePacked(bytes4(keccak256(bytes(_signature))), _calldata);
  }

  function _jumpToActiveProposal(uint256 _proposalId) internal {
    uint256 _snapshot = governorBravo.proposalSnapshot(_proposalId);
    vm.roll(_snapshot + 1);

    // Ensure the proposal is now Active
    IGovernor.ProposalState _state = governorBravo.state(_proposalId);
    assertEq(_state, IGovernor.ProposalState.Active);
  }

  function _jumpToVotingComplete(uint256 _proposalId) internal {
    // Jump one block past the proposal voting deadline
    uint256 _deadline = governorBravo.proposalDeadline(_proposalId);
    vm.roll(_deadline + 1);
  }

  function _jumpPastProposalEta(uint256 _proposalId) internal {
    uint256 _eta = governorBravo.proposalEta(_proposalId);
    vm.roll(block.number + 1);
    vm.warp(_eta + 1);
  }

  function _delegatesVoteOnBravoGovernor(uint256 _proposalId, uint8 _support) internal {
    require(_support < 3, "Invalid value for support");

    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorBravo.castVote(_proposalId, _support);
    }
  }

  function _buildTokenSendProposal(address _token, uint256 _tokenAmount, address _receiver)
    internal
    pure
    returns (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldata,
      string memory _description
    )
  {
    // Craft a new proposal to send _token.
    _targets = new address[](1);
    _values = new uint256[](1);
    _calldata = new bytes[](1);

    _targets[0] = _token;
    _values[0] = 0;
    _calldata[0] =
      _buildProposalData("transfer(address,uint256)", abi.encode(_receiver, _tokenAmount));
    _description = "Transfer some tokens from the new Governor";
  }

  function _submitTokenSendProposalToGovernorBravo(
    address _token,
    uint256 _amount,
    address _receiver
  )
    internal
    returns (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldata,
      string memory _description
    )
  {
    (_targets, _values, _calldata, _description) =
      _buildTokenSendProposal(_token, _amount, _receiver);

    // Submit the new proposal
    vm.prank(PROPOSER);
    _newProposalId = governorBravo.propose(_targets, _values, _calldata, _description);

    // Ensure proposal is in the expected state
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);
  }

  // Take a proposal through its full lifecycle, from proposing it, to voting on
  // it, to queuing it, to executing it (if relevant) via GovernorBravo.
  function _queueAndVoteAndExecuteProposalWithBravoGovernor(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description,
    uint8 _voteType
  ) internal {
    // Submit the new proposal
    vm.prank(PROPOSER);
    uint256 _newProposalId = governorBravo.propose(
      _targets, // Go away formatter!
      _values,
      _calldatas,
      _description
    );

    // Ensure proposal is Pending.
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);

    _jumpToActiveProposal(_newProposalId);

    // Have all delegates cast their weight with the specified support type.
    _delegatesVoteOnBravoGovernor(_newProposalId, _voteType);

    _jumpToVotingComplete(_newProposalId);

    _state = governorBravo.state(_newProposalId);
    if (_voteType == AGAINST || _voteType == ABSTAIN) {
      // The proposal should have failed.
      assertEq(_state, IGovernor.ProposalState.Defeated);

      // Attempt to queue the proposal.
      vm.expectRevert("Governor: proposal not successful");
      governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

      _jumpPastProposalEta(_newProposalId);

      // Attempt to execute the proposal.
      vm.expectRevert("Governor: proposal not successful");
      governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

      // Exit this function, there's nothing left to test.
      return;
    }

    // The voteType was FOR. Ensure the proposal has succeeded.
    assertEq(_state, IGovernor.ProposalState.Succeeded);

    // Queue the proposal
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is queued
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Queued);

    _jumpPastProposalEta(_newProposalId);

    // Execute the proposal
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);
  }

  function assertEq(IGovernor.ProposalState _actual, IGovernor.ProposalState _expected) internal {
    assertEq(uint8(_actual), uint8(_expected));
  }
}

abstract contract BravoGovernorProposalTest is GovernorBravoProposalHelper {
  function setUp() public virtual override(ProposalTestHelper) {
    ProposalTestHelper.setUp();
  }

  function testFuzz_NewGovernorCanReceiveNewProposal(uint256 _gtcAmount, address _gtcReceiver)
    public
  {
    _assumeReceiver(_gtcReceiver);
    _upgradeToBravoGovernor();
    _submitTokenSendProposalToGovernorBravo(address(gtcToken), _gtcAmount, _gtcReceiver);
  }

  function testFuzz_NewGovernorCanDefeatProposal(uint256 _amount, address _receiver, uint256 _seed)
    public
  {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    _upgradeToBravoGovernor();

    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildTokenSendProposal(address(_token), _amount, _receiver);

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      _calldatas,
      _description,
      (_amount % 2 == 1 ? AGAINST : ABSTAIN) // Randomize vote type.
    );

    // It should not be possible to queue the proposal
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }

  function testFuzz_NewGovernorCanPassProposalToSendToken(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);
    uint256 _initialTokenBalance = _token.balanceOf(_receiver);

    _upgradeToBravoGovernor();

    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildTokenSendProposal(address(_token), _amount, _receiver);

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets, _values, _calldatas, _description, FOR
    );

    // Ensure the tokens have been transferred
    assertEq(_token.balanceOf(_receiver), _initialTokenBalance + _amount);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amount);
  }

  function testFuzz_NewGovernorCanPassProposalToSendETH(uint256 _amount, address _receiver) public {
    _assumeReceiver(_receiver);
    vm.deal(TIMELOCK, _amount);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      new bytes[](1), // There is no calldata for a plain ETH call.
      "Transfer some ETH via the new Governor",
      FOR // Vote/suppport type.
    );

    // Ensure the ETH was transferred.
    assertEq(_receiver.balance, _receiverETHBalance + _amount);
    assertEq(TIMELOCK.balance, _timelockETHBalance - _amount);
  }

  function testFuzz_NewGovernorCanPassProposalToSendETHWithTokens(
    uint256 _amountETH,
    uint256 _amountToken,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    vm.deal(TIMELOCK, _amountETH);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    // Bound _amountToken by the number of tokens the timelock currently controls.
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    _amountToken = bound(_amountToken, 0, _timelockTokenBalance);

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH and tokens.
    address[] memory _targets = new address[](2);
    uint256[] memory _values = new uint256[](2);
    bytes[] memory _calldatas = new bytes[](2);

    // First call transfers tokens.
    _targets[0] = address(_token);
    _calldatas[0] =
      _buildProposalData("transfer(address,uint256)", abi.encode(_receiver, _amountToken));

    // Second call sends ETH.
    _targets[1] = _receiver;
    _values[1] = _amountETH;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      _calldatas,
      "Transfer tokens and ETH via the new Governor",
      FOR // Vote/suppport type.
    );

    // Ensure the ETH was transferred.
    assertEq(_receiver.balance, _receiverETHBalance + _amountETH);
    assertEq(TIMELOCK.balance, _timelockETHBalance - _amountETH);

    // Ensure the tokens were transferred.
    assertEq(_token.balanceOf(_receiver), _receiverTokenBalance + _amountToken);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amountToken);
  }

  function testFuzz_NewGovernorFailedProposalsCantSendETH(uint256 _amount, address _receiver)
    public
  {
    _assumeReceiver(_receiver);
    vm.deal(TIMELOCK, _amount);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      new bytes[](1), // There is no calldata for a plain ETH call.
      "Transfer some ETH via the new Governor",
      (_amount % 2 == 1 ? AGAINST : ABSTAIN) // Randomize vote type.
    );

    // Ensure ETH was *not* transferred.
    assertEq(_receiver.balance, _receiverETHBalance);
    assertEq(TIMELOCK.balance, _timelockETHBalance);
  }

  function testFuzz_NewGovernorCanUpdateSettingsViaSuccessfulProposal(
    uint256 _newDelay,
    uint256 _newVotingPeriod,
    uint256 _newProposalThreshold
  ) public {
    // The upper bounds are arbitrary here.
    _newDelay = bound(_newDelay, 0, 50_000); // about a week at 1 block per 12s
    _newVotingPeriod = bound(_newVotingPeriod, 1, 200_000); // about a month
    _newProposalThreshold = bound(_newProposalThreshold, 0, 42 ether);

    _upgradeToBravoGovernor();

    address[] memory _targets = new address[](3);
    uint256[] memory _values = new uint256[](3);
    bytes[] memory _calldatas = new bytes[](3);
    string memory _description = "Update governance settings";

    _targets[0] = address(governorBravo);
    _calldatas[0] = _buildProposalData("setVotingDelay(uint256)", abi.encode(_newDelay));

    _targets[1] = address(governorBravo);
    _calldatas[1] = _buildProposalData("setVotingPeriod(uint256)", abi.encode(_newVotingPeriod));

    _targets[2] = address(governorBravo);
    _calldatas[2] =
      _buildProposalData("setProposalThreshold(uint256)", abi.encode(_newProposalThreshold));

    // Submit the new proposal
    vm.prank(PROPOSER);
    uint256 _newProposalId = governorBravo.propose(_targets, _values, _calldatas, _description);

    // Ensure proposal is in the expected state
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);

    _jumpToActiveProposal(_newProposalId);

    _delegatesVoteOnBravoGovernor(_newProposalId, FOR);
    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has succeeded
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Succeeded);

    // Queue the proposal
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is queued
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Queued);

    _jumpPastProposalEta(_newProposalId);

    // Execute the proposal
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);

    // Confirm that governance settings have updated.
    assertEq(governorBravo.votingDelay(), _newDelay);
    assertEq(governorBravo.votingPeriod(), _newVotingPeriod);
    assertEq(governorBravo.proposalThreshold(), _newProposalThreshold);
  }

  function testFuzz_NewGovernorCanPassMixedProposal(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);
    uint256 _initialTokenBalance = _token.balanceOf(_receiver);

    _upgradeToBravoGovernor();
    (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    _jumpToActiveProposal(_newProposalId);

    // Delegates vote with a mix of For/Against/Abstain with For winning.
    vm.prank(delegates[0].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[1].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[2].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[3].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[4].addr);
    governorBravo.castVote(_newProposalId, ABSTAIN);
    vm.prank(delegates[5].addr);
    governorBravo.castVote(_newProposalId, AGAINST);

    // The vote should pass. We are asserting against the raw delegate voting
    // weight as a sanity check. In the event that the fork block is changed and
    // voting weights are materially different than they were when the test was
    // written, we want this assertion to fail.
    assertGt(
      delegates[0].votes + delegates[1].votes + delegates[2].votes, // FOR votes.
      delegates[3].votes + delegates[5].votes // AGAINST votes.
    );

    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has succeeded
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Succeeded);

    // Queue the proposal
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    _jumpPastProposalEta(_newProposalId);

    // Execute the proposal
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);

    // Ensure the tokens have been transferred
    assertEq(_token.balanceOf(_receiver), _initialTokenBalance + _amount);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amount);
  }

  function testFuzz_NewGovernorCanDefeatMixedProposal(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    _upgradeToBravoGovernor();
    (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    _jumpToActiveProposal(_newProposalId);

    // Delegates vote with a mix of For/Against/Abstain with Against/Abstain winning.
    vm.prank(delegates[0].addr);
    governorBravo.castVote(_newProposalId, ABSTAIN);
    vm.prank(delegates[1].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[2].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[3].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[4].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[5].addr);
    governorBravo.castVote(_newProposalId, FOR);

    // The vote should fail. We are asserting against the raw delegate voting
    // weight as a sanity check. In the event that the fork block is changed and
    // voting weights are materially different than they were when the test was
    // written, we want this assertion to fail.
    assertLt(
      delegates[1].votes + delegates[5].votes, // FOR votes.
      delegates[2].votes + delegates[3].votes + delegates[4].votes // AGAINST votes.
    );

    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has failed
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Defeated);

    // It should not be possible to queue the proposal
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }

  struct NewGovernorUnaffectedByVotesOnOldGovernorVars {
    uint256 alphaProposalId;
    address[] alphaTargets;
    uint256[] alphaValues;
    string[] alphaSignatures;
    bytes[] alphaCalldatas;
    string alphaDescription;
    uint256 bravoProposalId;
    address[] bravoTargets;
    uint256[] bravoValues;
    bytes[] bravoCalldatas;
    string bravoDescription;
  }

  function testFuzz_NewGovernorUnaffectedByVotesOnOldGovernor(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    NewGovernorUnaffectedByVotesOnOldGovernorVars memory _vars;
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    _upgradeToBravoGovernor();

    // Create a new proposal to send the token.
    _vars.alphaTargets = new address[](1);
    _vars.alphaValues = new uint256[](1);
    _vars.alphaSignatures = new string [](1);
    _vars.alphaCalldatas = new bytes[](1);
    _vars.alphaDescription = "Transfer some tokens from the new Governor";

    _vars.alphaTargets[0] = address(_token);
    _vars.alphaSignatures[0] = "transfer(address,uint256)";
    _vars.alphaCalldatas[0] = abi.encode(_receiver, _amount);

    // Submit the new proposal to Governor Alpha, which is now deprecated.
    vm.prank(PROPOSER);
    _vars.alphaProposalId = governorAlpha.propose(
      _vars.alphaTargets,
      _vars.alphaValues,
      _vars.alphaSignatures,
      _vars.alphaCalldatas,
      _vars.alphaDescription
    );

    // Now construct and submit an identical proposal on Governor Bravo, which is active.
    (
      _vars.bravoProposalId,
      _vars.bravoTargets,
      _vars.bravoValues,
      _vars.bravoCalldatas,
      _vars.bravoDescription
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    assertEq(
      uint8(governorAlpha.state(_vars.alphaProposalId)),
      uint8(governorBravo.state(_vars.bravoProposalId))
    );

    _jumpToActiveProposal(_vars.bravoProposalId);

    // Defeat the proposal on Bravo.
    assertEq(governorBravo.state(_vars.bravoProposalId), IGovernor.ProposalState.Active);
    _delegatesVoteOnBravoGovernor(_vars.bravoProposalId, AGAINST);

    // Pass the proposal on Alpha.
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(_vars.alphaProposalId, true);
    }

    _jumpToVotingComplete(_vars.bravoProposalId);

    // Ensure the Bravo proposal has failed and Alpha has succeeded.
    assertEq(governorBravo.state(_vars.bravoProposalId), IGovernor.ProposalState.Defeated);
    assertEq(governorAlpha.state(_vars.alphaProposalId), uint8(IGovernor.ProposalState.Succeeded));

    // It should not be possible to queue either proposal, confirming that votes
    // on alpha do not affect votes on bravo.
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(
      _vars.bravoTargets,
      _vars.bravoValues,
      _vars.bravoCalldatas,
      keccak256(bytes(_vars.bravoDescription))
    );
    vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
    governorAlpha.queue(_vars.alphaProposalId);
  }
}

abstract contract FlexVotingTest is GovernorBravoProposalHelper {
  using FixedPointMathLib for uint256;

  // Store the id of a new proposal unrelated to governor upgrade.
  uint256 newProposalId;

  event VoteCastWithParams(
    address indexed voter,
    uint256 proposalId,
    uint8 support,
    uint256 weight,
    string reason,
    bytes params
  );

  function setUp() public virtual override(ProposalTestHelper) {
    ProposalTestHelper.setUp();

    _upgradeToBravoGovernor();

    (newProposalId,,,,) = _submitTokenSendProposalToGovernorBravo(
      address(usdcToken), usdcToken.balanceOf(TIMELOCK), makeAddr("receiver for FlexVoting tests")
    );

    _jumpToActiveProposal(newProposalId);
  }

  function testFuzz_GovernorBravoSupportsCastingSplitVotes(
    uint256 _forVotePercentage,
    uint256 _againstVotePercentage,
    uint256 _abstainVotePercentage
  ) public {
    _forVotePercentage = bound(_forVotePercentage, 0.0e18, 1.0e18);
    _againstVotePercentage = bound(_againstVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage);
    _abstainVotePercentage =
      bound(_abstainVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage - _againstVotePercentage);

    // Attempt to split vote weight on this new proposal.
    uint256 _votingSnapshot = governorBravo.proposalSnapshot(newProposalId);
    uint256 _totalForVotes;
    uint256 _totalAgainstVotes;
    uint256 _totalAbstainVotes;
    for (uint256 _i; _i < delegates.length; _i++) {
      address _voter = delegates[_i].addr;
      uint256 _weight = gtcToken.getPriorVotes(_voter, _votingSnapshot);

      uint128 _forVotes = uint128(_weight.mulWadDown(_forVotePercentage));
      uint128 _againstVotes = uint128(_weight.mulWadDown(_againstVotePercentage));
      uint128 _abstainVotes = uint128(_weight.mulWadDown(_abstainVotePercentage));
      bytes memory _fractionalizedVotes = abi.encodePacked(_againstVotes, _forVotes, _abstainVotes);
      _totalForVotes += _forVotes;
      _totalAgainstVotes += _againstVotes;
      _totalAbstainVotes += _abstainVotes;

      // The accepted support types for Bravo fall within [0,2].
      uint8 _supportTypeDoesntMatterForFlexVoting = uint8(bound(_i, 0, 2));

      vm.expectEmit(true, true, true, true);
      emit VoteCastWithParams(
        _voter,
        newProposalId,
        _supportTypeDoesntMatterForFlexVoting, // Really: support type is ignored.
        _weight,
        "I do what I want",
        _fractionalizedVotes
      );

      // This call should succeed.
      vm.prank(_voter);
      governorBravo.castVoteWithReasonAndParams(
        newProposalId,
        _supportTypeDoesntMatterForFlexVoting,
        "I do what I want",
        _fractionalizedVotes
      );
    }

    // Ensure the votes were split.
    (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) =
      governorBravo.proposalVotes(newProposalId);
    assertEq(_totalForVotes, _actualForVotes);
    assertEq(_totalAgainstVotes, _actualAgainstVotes);
    assertEq(_totalAbstainVotes, _actualAbstainVotes);
  }

  struct VoteData {
    uint128 forVotes;
    uint128 againstVotes;
    uint128 abstainVotes;
  }

  function testFuzz_GovernorBravoSupportsCastingPartialSplitVotes(
    uint256 _firstVotePercentage,
    uint256 _forVotePercentage,
    uint256 _againstVotePercentage,
    uint256 _abstainVotePercentage
  ) public {
    // This is the % of total weight that will be cast the first time.
    _firstVotePercentage = bound(_firstVotePercentage, 0.1e18, 0.9e18);

    _forVotePercentage = bound(_forVotePercentage, 0.0e18, 1.0e18);
    _againstVotePercentage = bound(_againstVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage);
    _abstainVotePercentage =
      bound(_abstainVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage - _againstVotePercentage);

    uint256 _weight = gtcToken.getPriorVotes(
      PROPOSER, // The proposer is also the top delegate.
      governorBravo.proposalSnapshot(newProposalId)
    );

    // The accepted support types for Bravo fall within [0,2].
    uint8 _supportTypeDoesntMatterForFlexVoting = uint8(2);

    // Cast partial vote the first time.
    VoteData memory _firstVote;
    uint256 _voteWeight = _weight.mulWadDown(_firstVotePercentage);
    _firstVote.forVotes = uint128(_voteWeight.mulWadDown(_forVotePercentage));
    _firstVote.againstVotes = uint128(_voteWeight.mulWadDown(_againstVotePercentage));
    _firstVote.abstainVotes = uint128(_voteWeight.mulWadDown(_abstainVotePercentage));
    vm.prank(PROPOSER);
    governorBravo.castVoteWithReasonAndParams(
      newProposalId,
      _supportTypeDoesntMatterForFlexVoting,
      "My first vote",
      abi.encodePacked(_firstVote.againstVotes, _firstVote.forVotes, _firstVote.abstainVotes)
    );

    ( // Ensure the votes were recorded.
    uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governorBravo.proposalVotes(newProposalId);
    assertEq(_firstVote.forVotes, _forVotesCast);
    assertEq(_firstVote.againstVotes, _againstVotesCast);
    assertEq(_firstVote.abstainVotes, _abstainVotesCast);

    // Cast partial vote the second time.
    VoteData memory _secondVote;
    _voteWeight = _weight.mulWadDown(1e18 - _firstVotePercentage);
    _secondVote.forVotes = uint128(_voteWeight.mulWadDown(_forVotePercentage));
    _secondVote.againstVotes = uint128(_voteWeight.mulWadDown(_againstVotePercentage));
    _secondVote.abstainVotes = uint128(_voteWeight.mulWadDown(_abstainVotePercentage));
    vm.prank(PROPOSER);
    governorBravo.castVoteWithReasonAndParams(
      newProposalId,
      _supportTypeDoesntMatterForFlexVoting,
      "My second vote",
      abi.encodePacked(_secondVote.againstVotes, _secondVote.forVotes, _secondVote.abstainVotes)
    );

    ( // Ensure the new votes were recorded.
    _againstVotesCast, _forVotesCast, _abstainVotesCast) =
      governorBravo.proposalVotes(newProposalId);
    assertEq(_firstVote.forVotes + _secondVote.forVotes, _forVotesCast);
    assertEq(_firstVote.againstVotes + _secondVote.againstVotes, _againstVotesCast);
    assertEq(_firstVote.abstainVotes + _secondVote.abstainVotes, _abstainVotesCast);

    // Confirm nominal votes can co-exist with partial+fractional votes by
    // voting with the second largest delegate.
    uint256 _nominalVoterWeight =
      gtcToken.getPriorVotes(delegates[1].addr, governorBravo.proposalSnapshot(newProposalId));
    vm.prank(delegates[1].addr);
    governorBravo.castVote(newProposalId, FOR);

    ( // Ensure the nominal votes were recorded.
    _againstVotesCast, _forVotesCast, _abstainVotesCast) =
      governorBravo.proposalVotes(newProposalId);
    assertEq(_firstVote.forVotes + _secondVote.forVotes + _nominalVoterWeight, _forVotesCast);
    assertEq(_firstVote.againstVotes + _secondVote.againstVotes, _againstVotesCast);
    assertEq(_firstVote.abstainVotes + _secondVote.abstainVotes, _abstainVotesCast);
  }

  function testFuzz_ProposalsCanBePassedWithSplitVotes(
    uint256 _forVotePercentage,
    uint256 _againstVotePercentage,
    uint256 _abstainVotePercentage
  ) public {
    _forVotePercentage = bound(_forVotePercentage, 0.0e18, 1.0e18);
    _againstVotePercentage = bound(_againstVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage);
    _abstainVotePercentage =
      bound(_abstainVotePercentage, 0.0e18, 1.0e18 - _forVotePercentage - _againstVotePercentage);

    uint256 _weight = gtcToken.getPriorVotes(
      PROPOSER, // The proposer is also the top delegate.
      governorBravo.proposalSnapshot(newProposalId)
    );

    uint128 _forVotes = uint128(_weight.mulWadDown(_forVotePercentage));
    uint128 _againstVotes = uint128(_weight.mulWadDown(_againstVotePercentage));
    uint128 _abstainVotes = uint128(_weight.mulWadDown(_abstainVotePercentage));

    // The accepted support types for Bravo fall within [0,2].
    uint8 _supportTypeDoesntMatterForFlexVoting = uint8(2);

    vm.prank(PROPOSER);
    governorBravo.castVoteWithReasonAndParams(
      newProposalId,
      _supportTypeDoesntMatterForFlexVoting,
      "My vote",
      abi.encodePacked(_againstVotes, _forVotes, _abstainVotes)
    );

    ( // Ensure the votes were split.
    uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) =
      governorBravo.proposalVotes(newProposalId);
    assertEq(_forVotes, _actualForVotes);
    assertEq(_againstVotes, _actualAgainstVotes);
    assertEq(_abstainVotes, _actualAbstainVotes);

    _jumpToVotingComplete(newProposalId);

    IGovernor.ProposalState _state = governorBravo.state(newProposalId);

    if (_forVotes >= governorBravo.quorum(block.number) && _forVotes > _againstVotes) {
      assertEq(_state, IGovernor.ProposalState.Succeeded);
    } else {
      assertEq(_state, IGovernor.ProposalState.Defeated);
    }
  }
}

// Exercise the existing Bravo contract deployed on April 7th 2023.
contract BravoGovernorDeployTestWithExistingBravo is BravoGovernorDeployTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return true;
  }
}

contract AlphaGovernorPreProposalTestWithExistingBravo is AlphaGovernorPreProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return true;
  }
}

contract AlphaGovernorPostProposalTestWithExistingBravo is AlphaGovernorPostProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return true;
  }
}

contract BravoGovernorProposalTestWithExistingBravo is BravoGovernorProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return true;
  }
}

contract FlexVotingTestWithExistingBravo is FlexVotingTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return true;
  }
}

// Exercise a fresh Bravo deploy.
contract BravoGovernorDeployTestWithBravoDeployedByScript is BravoGovernorDeployTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

contract AlphaGovernorPreProposalTestWithBravoDeployedByScript is AlphaGovernorPreProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

contract AlphaGovernorPostProposalTestWithBravoDeployedByScript is AlphaGovernorPostProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

contract BravoGovernorProposalTestWithBravoDeployedByScript is BravoGovernorProposalTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

contract FlexVotingTestWithBravoDeployedByScript is FlexVotingTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}
