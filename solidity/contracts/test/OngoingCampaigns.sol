// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {OngoingCampaigns, IERC20} from '../OngoingCampaigns.sol';

contract OngoingCampaignsMock is OngoingCampaigns {
  struct ClaimParams {
    bytes32 campaign;
    address claimee;
    address recipient;
  }

  ClaimParams public internalClaimCall;
  TokenAmount[] internal _internalClaimCallTokensAmounts;
  bytes32[] internal _internalClaimCallProof;

  constructor(address _superAdmin, address[] memory _initialAdmins) OngoingCampaigns(_superAdmin, _initialAdmins) {}

  function getInternalClaimCallProof() external view returns (bytes32[] memory _proof) {
    _proof = new bytes32[](_internalClaimCallProof.length);
    for (uint256 i; i < _internalClaimCallProof.length; i++) {
      _proof[i] = _internalClaimCallProof[i];
    }
  }

  function getInternalClaimCallTokensAmounts() external view returns (TokenAmount[] memory _tokensAmounts) {
    _tokensAmounts = new TokenAmount[](_internalClaimCallTokensAmounts.length);
    for (uint256 i; i < _internalClaimCallTokensAmounts.length; i++) {
      _tokensAmounts[i] = _internalClaimCallTokensAmounts[i];
    }
  }

  function setTotalAirdroppedByCampaignAndToken(
    bytes32 _campaign,
    IERC20 _token,
    uint256 _amount
  ) external {
    _totalAirdroppedByCampaignAndToken[_getIdOfCampaignAndToken(_campaign, _token)] = _amount;
  }

  function setTotalClaimedByCampaignAndToken(
    bytes32 _campaign,
    IERC20 _token,
    uint256 _amount
  ) external {
    _totalClaimedByCampaignAndToken[_getIdOfCampaignAndToken(_campaign, _token)] = _amount;
  }

  function _claim(
    bytes32 _campaign,
    address _claimee,
    address _recipient,
    TokenAmount[] calldata _tokensAmounts,
    bytes32[] calldata _proof
  ) internal override {
    for (uint256 i = 0; i < _tokensAmounts.length; i++) {
      _internalClaimCallTokensAmounts.push(_tokensAmounts[i]);
    }
    for (uint256 i = 0; i < _proof.length; i++) {
      _internalClaimCallProof.push(_proof[i]);
    }
    internalClaimCall = ClaimParams(_campaign, _claimee, _recipient);
  }

  function internalClaim(
    bytes32 _campaign,
    address _claimee,
    address _recipient,
    TokenAmount[] calldata _tokensAmounts,
    bytes32[] calldata _proof
  ) external {
    super._claim(_campaign, _claimee, _recipient, _tokensAmounts, _proof);
  }
}
