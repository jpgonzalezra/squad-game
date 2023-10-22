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

        SquadGame.Scenary[] memory scenaries = new SquadGame.Scenary[](5);
        scenaries[0].increases = [1, 0, 0, 2, 0, 0, 0, 2, 0, 0];
        scenaries[0].decreases = [0, 2, 0, 0, 1, 0, 0, 0, 1, 2];

        scenaries[1].increases = [2, 0, 1, 2, 0, 0, 1, 2, 0, 0];
        scenaries[1].decreases = [0, 1, 0, 0, 0, 0, 0, 0, 2, 2];

        scenaries[2].increases = [0, 1, 0, 1, 0, 0, 0, 1, 0, 0];
        scenaries[2].decreases = [0, 0, 0, 0, 2, 0, 0, 0, 0, 0];

        scenaries[3].increases = [1, 0, 0, 1, 0, 0, 0, 1, 0, 0];
        scenaries[3].decreases = [0, 2, 0, 0, 1, 0, 0, 0, 1, 1];

        scenaries[4].increases = [0, 0, 0, 2, 0, 0, 0, 0, 0, 0];
        scenaries[4].decreases = [0, 0, 0, 0, 1, 0, 0, 0, 1, 0];
        
        new SquadGame(keyHash, vrfCoordinator, subscriptionId, scenaries);

        vm.stopBroadcast();
    }
}
