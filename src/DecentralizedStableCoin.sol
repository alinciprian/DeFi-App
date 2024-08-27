//SPDX-License-Identifier:MIT

import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

pragma solidity ^0.8.18;

/**
 * @title Decentralized Stable Coin
 * @author AlinCiprian
 * Collateral: Exogenous(wETH & wBTC)
 * Minting: Alghoritmic
 * Relative Stability: Pegged to USD
 *
 * This contract is meant to be governed by DSCEngine. Here is just ERC20 implementation of
 * a stablecoin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin___MustBeMoreThanZero();
    error DecentralizedStableCoin___BurnAmountExceedsBalance();
    error DecentralizedStableCoin___NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin___MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin___BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin___NotZeroAddress();
        }
        if (_amount < 0) {
            revert DecentralizedStableCoin___MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
