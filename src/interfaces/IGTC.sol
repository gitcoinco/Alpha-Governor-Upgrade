// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface IGTC {
  event Approval(address indexed owner, address indexed spender, uint256 amount);
  event DelegateChanged(
    address indexed delegator, address indexed fromDelegate, address indexed toDelegate
  );
  event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
  event GTCDistChanged(address delegator, address delegatee);
  event MinterChanged(address minter, address newMinter);
  event Transfer(address indexed from, address indexed to, uint256 amount);

  function DELEGATION_TYPEHASH() external view returns (bytes32);
  function DOMAIN_TYPEHASH() external view returns (bytes32);
  function GTCDist() external view returns (address);
  function PERMIT_TYPEHASH() external view returns (bytes32);
  function allowance(address account, address spender) external view returns (uint256);
  function approve(address spender, uint256 rawAmount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
  function checkpoints(address, uint32) external view returns (uint32 fromBlock, uint96 votes);
  function decimals() external view returns (uint8);
  function delegate(address delegatee) external;
  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
  function delegateOnDist(address delegator, address delegatee) external;
  function delegates(address) external view returns (address);
  function getCurrentVotes(address account) external view returns (uint96);
  function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
  function minimumTimeBetweenMints() external view returns (uint32);
  function mint(address dst, uint256 rawAmount) external;
  function mintCap() external view returns (uint8);
  function minter() external view returns (address);
  function mintingAllowedAfter() external view returns (uint256);
  function name() external view returns (string memory);
  function nonces(address) external view returns (uint256);
  function numCheckpoints(address) external view returns (uint32);
  function permit(
    address owner,
    address spender,
    uint256 rawAmount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
  function setGTCDist(address GTCDist_) external;
  function setMinter(address minter_) external;
  function symbol() external view returns (string memory);
  function totalSupply() external view returns (uint256);
  function transfer(address dst, uint256 rawAmount) external returns (bool);
  function transferFrom(address src, address dst, uint256 rawAmount) external returns (bool);
}
