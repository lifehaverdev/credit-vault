// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CharteredFundImplementation} from "../../src/CharteredFundImplementation.sol";

contract CharteredFundImplementationV2 is CharteredFundImplementation {
    function version() external pure returns (uint256) {
        return 2;
    }
}
