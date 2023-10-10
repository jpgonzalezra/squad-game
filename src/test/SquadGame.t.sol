// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SquadGame.sol";
import "./mocks/MockVRFCoordinatorV2.sol";
import "./mocks/LinkToken.sol";
import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Utilities} from "./utils/Utilities.sol";
import "forge-std/console.sol";

contract SquadGameTest is Test {
    event SquadCreated(bytes32 squadId, uint8[10] attributes);
    event MissionCreated(uint8 missionId);
    event JoinedMission(bytes32 squadId, uint8 missionId);
    event StartedMission(uint8 missionId, uint256 requestId);
    event FinishedMission(uint8 missionId);
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);

    struct SquadInfo {
        address lider;
        bytes32 squadId;
        uint8[10] attributes;
    }

    LinkToken public linkToken;
    MockVRFCoordinatorV2 public vrfCoordinator;
    SquadGame public game;
    Utilities internal utils;

    uint96 constant FUND_AMOUNT = 1 * 10 ** 18;

    // Initialized as blank, fine for testing
    uint64 subId;
    bytes32 keyHash; // gasLane

    event ReturnedRandomness(uint256[] randomWords);

    function setUp() public {
        utils = new Utilities();
        linkToken = new LinkToken();
        vrfCoordinator = new MockVRFCoordinatorV2();
        subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subId, FUND_AMOUNT);
        game = new SquadGame(keyHash, address(vrfCoordinator), subId);
        vrfCoordinator.addConsumer(subId, address(game));
    }

    function testCreateMission() public {
        vm.expectEmit(true, true, true, true);
        emit MissionCreated(1);
        game.createMission(1, 8, 0.1 ether);
        (
            uint256 fee,
            uint8 id,
            uint8 minParticipantsPerMission,
            SquadGame.MissionState state
        ) = game.missionInfoByMissionId(1);
        assertTrue(state == SquadGame.MissionState.Ready);
        assertTrue(minParticipantsPerMission == 8);
        assertTrue(fee == 0.1 ether);
    }

    function testAlreadyMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 1, 0.1 ether);
        vm.expectRevert(SquadGame.AlreadyMission.selector);
        game.createMission(missionId, 1, 0.1 ether);
    }

    function testCreateSquad() public {
        // create squad successfully
        address owner = address(1);
        vm.startPrank(owner);
        (bytes32 squadId, uint8[10] memory attributes) = createSquad(
            8,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );

        vm.expectEmit(true, true, true, true);
        emit SquadCreated(squadId, attributes);
        game.createSquad(attributes);

        assertTrue(game.squadIdsByLider(owner, squadId));

        (
            uint8[10] memory squadInfoAttributes,
            SquadGame.SquadState squadInfoState
        ) = game.getSquadInfoBySquadId(squadId);

        assertTrue(squadInfoAttributes[0] == 8);
        assertTrue(squadInfoAttributes[1] == 5);
        assertTrue(squadInfoAttributes[2] == 3);
        assertTrue(squadInfoAttributes[3] == 7);
        assertTrue(squadInfoAttributes[4] == 1);
        assertTrue(squadInfoAttributes[5] == 9);
        assertTrue(squadInfoAttributes[6] == 3);
        assertTrue(squadInfoAttributes[7] == 10);
        assertTrue(squadInfoAttributes[8] == 2);
        assertTrue(squadInfoAttributes[9] == 2);
        assertTrue(squadInfoState == SquadGame.SquadState.Formed);

        // should revert if squad already exists
        vm.expectRevert(SquadGame.SquadAlreadyExist.selector);
        game.createSquad(attributes);

        // should revert if attributes are invalid
        (, uint8[10] memory invalidAttribute) = createSquad(
            0,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );

        vm.expectRevert(SquadGame.InvalidAttribute.selector);
        game.createSquad(invalidAttribute);

        // should revert if attributes are invalid, the sum of attributes should be 50
        (, uint8[10] memory invalidAttributes) = createSquad(
            7,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );
        vm.expectRevert(SquadGame.AttributesSumNot50.selector);
        game.createSquad(invalidAttributes);

        vm.stopPrank();
    }

    function testJoinMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 5, 0.1 ether);

        address alice = address(2);
        utils.fundSpecificAddress(alice);

        vm.startPrank(alice);
        (bytes32 squadId, uint8[10] memory attributes) = createSquad(
            8,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );
        game.createSquad(attributes);

        vm.expectEmit(true, true, true, true);
        emit JoinedMission(squadId, missionId);
        game.joinMission{value: 0.1 ether}(squadId, missionId);
        vm.stopPrank();

        // should revert if squad is not the leader
        address bob = address(3);
        utils.fundSpecificAddress(bob);
        vm.startPrank(bob);
        (bytes32 squadId1, uint8[10] memory attributes1) = createSquad(
            8,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            3,
            1
        );
        game.createSquad(attributes1);

        vm.stopPrank();
        vm.expectRevert(SquadGame.NotALider.selector);
        game.joinMission{value: 0.1 ether}(squadId, missionId);

        // should revert if the mission is not ready
        // TODO:

        // should revert if squad is not formed
        // TODO:

        // should revert if payment is not enough
        // TODO:
    }

    function testStartMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 5, 0.1 ether);

        SquadInfo[] memory players = new SquadInfo[](5);

        (bytes32 squadId0, uint8[10] memory attributes0) = createSquad(
            8,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );
        players[0] = SquadInfo({
            lider: address(10),
            squadId: squadId0,
            attributes: attributes0
        });

        (bytes32 squadId1, uint8[10] memory attributes1) = createSquad(
            6,
            7,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );
        players[1] = SquadInfo({
            lider: address(11),
            squadId: squadId1,
            attributes: attributes1
        });

        (bytes32 squadId2, uint8[10] memory attributes2) = createSquad(
            8,
            5,
            3,
            5,
            2,
            9,
            3,
            10,
            3,
            2
        );
        players[2] = SquadInfo({
            lider: address(12),
            squadId: squadId2,
            attributes: attributes2
        });

        (bytes32 squadId3, uint8[10] memory attributes3) = createSquad(
            8,
            5,
            3,
            7,
            3,
            9,
            3,
            5,
            2,
            5
        );
        players[3] = SquadInfo({
            lider: address(13),
            squadId: squadId3,
            attributes: attributes3
        });

        (bytes32 squadId4, uint8[10] memory attributes4) = createSquad(
            7,
            4,
            2,
            6,
            1,
            7,
            3,
            10,
            6,
            4
        );
        players[4] = SquadInfo({
            lider: address(14),
            squadId: squadId4,
            attributes: attributes4
        });

        joinMission(players, missionId);

        game.startMission(missionId);

        // should revert if squad is not the leader
        // should revert if the mission is not ready
        // should revert if squad is not formed
        // should revert if payment is not enough
    }

    // function testCanRequestRandomness() public {
    //     // start mission
    //     uint256 startingRequestId = vrfConsumer.s_requestId();
    //     vrfConsumer.requestRandomWords();
    //     assertTrue(vrfConsumer.s_requestId() != startingRequestId);
    // }

    function testFinishMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 1, 0.1 ether);

        address alice = address(2);
        vm.startPrank(alice);
        utils.fundSpecificAddress(alice);

        (bytes32 squadId, uint8[10] memory attributes) = createSquad(
            8,
            5,
            3,
            7,
            1,
            9,
            3,
            10,
            2,
            2
        );
        game.createSquad(attributes);

        game.joinMission{value: 0.1 ether}(squadId, missionId);
        vm.stopPrank();

        game.startMission(missionId);

        uint256 requestId = 1;

        vm.expectEmit(true, true, true, true);
        emit FinishedMission(missionId);
        vrfCoordinator.fulfillRandomWords(requestId, address(game));

        uint256[] memory words = utils.getWords(requestId, game.NUMWORDS());
        (uint256 randomness, uint8 missionIdRequested) = game.requests(
            missionId
        );

        assertTrue(randomness == words[0]);
        assertTrue(missionIdRequested == 1);
    }

    function joinMission(SquadInfo[] memory players, uint8 missionId) private {
        for (uint8 i = 0; i < players.length; i++) {
            vm.startPrank(players[i].lider);
            utils.fundSpecificAddress(players[i].lider);

            game.createSquad(players[i].attributes);
            game.joinMission{value: 0.1 ether}(players[i].squadId, missionId);
            vm.stopPrank();
        }
    }

    function createSquad(
        uint8 attr1,
        uint8 attr2,
        uint8 attr3,
        uint8 attr4,
        uint8 attr5,
        uint8 attr6,
        uint8 attr7,
        uint8 attr8,
        uint8 attr9,
        uint8 attr10
    ) private pure returns (bytes32 squadId, uint8[10] memory attributes) {
        attributes = uint8[10](
            [
                attr1,
                attr2,
                attr3,
                attr4,
                attr5,
                attr6,
                attr7,
                attr8,
                attr9,
                attr10
            ]
        );

        squadId = keccak256(
            abi.encodePacked(
                [
                    attr1,
                    attr2,
                    attr3,
                    attr4,
                    attr5,
                    attr6,
                    attr7,
                    attr8,
                    attr9,
                    attr10
                ]
            )
        );
    }
}
