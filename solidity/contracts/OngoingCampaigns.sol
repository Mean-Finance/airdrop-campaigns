// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {IOngoingCampaigns} from '../interfaces/IOngoingCampaigns.sol';
import {AccessControlDefaultAdminRules} from '@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol';
import {SafeERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';

contract OngoingCampaigns is AccessControlDefaultAdminRules, IOngoingCampaigns {
  using SafeERC20 for IERC20;

  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  /// @inheritdoc IOngoingCampaigns
  mapping(bytes32 => bytes32) public roots;
  mapping(bytes32 => uint256) internal _amountClaimedByCampaignTokenAndClaimee;
  mapping(bytes32 => uint256) internal _totalAirdroppedByCampaignAndToken;
  mapping(bytes32 => uint256) internal _totalClaimedByCampaignAndToken;

  constructor(address _superAdmin, address[] memory _initialAdmins) AccessControlDefaultAdminRules(3 days, _superAdmin) {
    for (uint256 _i = 0; _i < _initialAdmins.length; ++_i) {
      _grantRole(ADMIN_ROLE, _initialAdmins[_i]);
    }
  }

  /// @inheritdoc IOngoingCampaigns
  function amountClaimed(
    bytes32 _campaign,
    IERC20 _token,
    address _claimee
  ) external view returns (uint256) {
    return _amountClaimedByCampaignTokenAndClaimee[_getIdOfCampaignTokenAndClaimee(_campaign, _token, _claimee)];
  }

  /// @inheritdoc IOngoingCampaigns
  function totalAirdropped(bytes32 _campaign, IERC20 _token) external view returns (uint256) {
    return _totalAirdroppedByCampaignAndToken[_getIdOfCampaignAndToken(_campaign, _token)];
  }

  /// @inheritdoc IOngoingCampaigns
  function totalClaimed(bytes32 _campaign, IERC20 _token) external view returns (uint256) {
    return _totalClaimedByCampaignAndToken[_getIdOfCampaignAndToken(_campaign, _token)];
  }

  /// @inheritdoc IOngoingCampaigns
  function updateCampaign(
    bytes32 _campaign,
    bytes32 _root,
    TokenAmount[] calldata _tokensAllocation
  ) external onlyRole(ADMIN_ROLE) {
    if (_campaign == bytes32(0)) revert InvalidCampaign();
    if (_root == bytes32(0)) revert InvalidMerkleRoot();
    if (_tokensAllocation.length == 0) revert InvalidTokenAmount();

    for (uint256 _i = 0; _i < _tokensAllocation.length; ++_i) {
      // Move from calldata to memory
      TokenAmount memory _tokenAllocation = _tokensAllocation[_i];

      // Build our unique ID for campaign and token address.
      bytes32 _campaignAndTokenId = _getIdOfCampaignAndToken(_campaign, _tokenAllocation.token);

      // Move storage var to memory.
      uint256 _currentTotalAirdropped = _totalAirdroppedByCampaignAndToken[_campaignAndTokenId];

      // We can not lower the amount of total claimable on a campaign since that would break
      // the maths for the "ongoing airdrops".
      if (_tokenAllocation.amount < _currentTotalAirdropped) revert InvalidTokenAmount();

      // Refill needed represents the amount of tokens needed to
      // transfer into the contract to allow every claimee to claim the updated rewards
      uint256 _refillNeeded;
      // We can use unchecked, since we have checked this in L57
      unchecked {
        _refillNeeded = _tokenAllocation.amount - _currentTotalAirdropped;
      }

      // Update total claimable reward on campaign
      _totalAirdroppedByCampaignAndToken[_campaignAndTokenId] = _tokenAllocation.amount;

      // Refill contract with the ERC20 tokens
      _tokenAllocation.token.safeTransferFrom(msg.sender, address(this), _refillNeeded);
    }

    // Update the information
    roots[_campaign] = _root;

    // Emit event
    emit CampaignUpdated(_campaign, _root, _tokensAllocation);
  }

  /// @inheritdoc IOngoingCampaigns
  function claimAndSendToClaimee(
    bytes32 _campaign,
    address _claimee,
    TokenAmount[] calldata _tokensAmounts,
    bytes32[] calldata _proof
  ) external {
    _claim(_campaign, _claimee, _claimee, _tokensAmounts, _proof);
  }

  /// @inheritdoc IOngoingCampaigns
  function claimAndTransfer(
    bytes32 _campaign,
    TokenAmount[] calldata _tokensAmounts,
    address _recipient,
    bytes32[] calldata _proof
  ) external {
    _claim(_campaign, msg.sender, _recipient, _tokensAmounts, _proof);
  }

  function _claim(
    bytes32 _campaign,
    address _claimee,
    address _recipient,
    TokenAmount[] calldata _tokensAmounts,
    bytes32[] calldata _proof
  ) internal virtual {
    // Basic checks
    if (_recipient == address(0)) revert ZeroAddress();
    if (_proof.length == 0) revert InvalidProof();

    {
      // Validate the proof and leaf information
      bytes32 _leaf = keccak256(abi.encodePacked(_claimee, _encode(_tokensAmounts)));
      bool _isValidLeaf = MerkleProof.verify(_proof, roots[_campaign], _leaf);
      if (!_isValidLeaf) revert InvalidProof();
    }

    // Go through every token being claimed and apply check-effects-interaction per token.
    uint256[] memory _claimed = new uint256[](_tokensAmounts.length);
    IERC20[] memory _tokens = new IERC20[](_tokensAmounts.length);
    for (uint256 _i = 0; _i < _tokensAmounts.length; ++_i) {
      TokenAmount memory _tokenAmount = _tokensAmounts[_i];

      // Build our unique ID for campaign, token and claimee address.
      bytes32 _campaignTokenAndClaimeeId = _getIdOfCampaignTokenAndClaimee(_campaign, _tokenAmount.token, _claimee);

      // Calculate to claim
      _claimed[_i] = _tokenAmount.amount - _amountClaimedByCampaignTokenAndClaimee[_campaignTokenAndClaimeeId];
      _tokens[_i] = _tokenAmount.token;

      if (_claimed[_i] > 0) {
        // Update the total amount claimed of the token and campaign for the claimee
        _amountClaimedByCampaignTokenAndClaimee[_campaignTokenAndClaimeeId] = _tokenAmount.amount;
        // Update the total claimed of a token on a campaign
        _totalClaimedByCampaignAndToken[_getIdOfCampaignAndToken(_campaign, _tokenAmount.token)] += _claimed[_i];
        // Send the recipient the claimed tokens
        _tokenAmount.token.safeTransfer(_recipient, _claimed[_i]);
      }
    }

    // Emit event
    emit Claimed(_campaign, _claimee, _recipient, _tokens, _claimed);
  }

  /// @inheritdoc IOngoingCampaigns
  function shutdown(
    bytes32 _campaign,
    IERC20[] calldata _tokens,
    address _recipient
  ) external onlyRole(ADMIN_ROLE) returns (uint256[] memory _unclaimed) {
    if (_recipient == address(0)) revert ZeroAddress();
    _unclaimed = new uint256[](_tokens.length);
    // We delete campaign setting it effectively to zero root, so users can't claim this campaign
    delete roots[_campaign];
    for (uint256 _i = 0; _i < _tokens.length; ++_i) {
      IERC20 _token = _tokens[_i];

      // Build our unique ID for campaign and token address.
      bytes32 _campaignAndTokenId = _getIdOfCampaignAndToken(_campaign, _token);

      // Understand how much is still available
      _unclaimed[_i] = _totalAirdroppedByCampaignAndToken[_campaignAndTokenId] - _totalClaimedByCampaignAndToken[_campaignAndTokenId];

      // We remove unecessary data so we get a little bit of gas back
      delete _totalClaimedByCampaignAndToken[_campaignAndTokenId];
      delete _totalAirdroppedByCampaignAndToken[_campaignAndTokenId];

      if (_unclaimed[_i] > 0) {
        // Transfer it out to recipient
        _token.safeTransfer(_recipient, _unclaimed[_i]);
      }
    }

    emit CampaignShutDown(_campaign, _tokens, _unclaimed, _recipient);
  }

  function _getIdOfCampaignAndToken(bytes32 _campaign, IERC20 _token) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_campaign, _token));
  }

  function _getIdOfCampaignTokenAndClaimee(
    bytes32 _campaign,
    IERC20 _token,
    address _claimee
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_campaign, _token, _claimee));
  }

  function _encode(TokenAmount[] calldata _tokenAmounts) internal pure returns (bytes memory _result) {
    for (uint256 _i = 0; _i < _tokenAmounts.length; ++_i) {
      _result = bytes.concat(_result, abi.encodePacked(_tokenAmounts[_i].token, _tokenAmounts[_i].amount));
    }
  }
}
