// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {VRFCoordinatorV2Mock as VRFCoordinatorMock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract MockVRFCoordinatorV2 is VRFCoordinatorMock {
    uint96 constant MOCK_BASE_FEE = 100000000000000000;
    uint96 constant MOCK_GAS_PRICE_LINK = 1e9;

    constructor() VRFCoordinatorMock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK) {}
}
