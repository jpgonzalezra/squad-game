// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import "../src/SquadGame.sol";
import "./HelperConfig.sol";
import "../src/test/mocks/LinkToken.sol";
import "../src/test/mocks/MockVRFCoordinatorV2.sol";

contract DeploySquadGame is Script, HelperConfig {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (
            ,
            ,
            ,
            address link,
            ,
            ,
            uint64 subscriptionId,
            address vrfCoordinator,
            bytes32 keyHash
        ) = helperConfig.activeNetworkConfig();

        if (link == address(0)) {
            link = address(new LinkToken());
        }

        if (vrfCoordinator == address(0)) {
            vrfCoordinator = address(new MockVRFCoordinatorV2());
        }

        vm.startBroadcast();

        int8[10][] memory scenarios = new int8[10][](2);
        scenarios[0] = [
            int8(2),
            int8(1),
            int8(-1),
            int8(2),
            int8(0),
            int8(-2),
            int8(1),
            int8(-1),
            int8(0),
            int8(2)
        ];
        scenarios[1] = [
            int8(1),
            int8(-2),
            int8(0),
            int8(2),
            int8(-1),
            int8(1),
            int8(2),
            int8(-2),
            int8(0),
            int8(1)
        ];
        new SquadGame(keyHash, vrfCoordinator, subscriptionId, scenarios);

        vm.stopBroadcast();
    }
}
