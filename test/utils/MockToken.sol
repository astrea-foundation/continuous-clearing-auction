// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC20ReturnFalseMock} from 'test/utils/ERC20Mock.sol';

contract MockToken is ERC20ReturnFalseMock {
    constructor() ERC20('MockFailingToken', 'FAIL') {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
