// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../LucidSwirl.sol";
import "./mocks/MockVRFCoordinatorV2.sol";
import "./mocks/LinkToken.sol";
import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Utilities} from "./utils/Utilities.sol";
// import "forge-std/console.sol";

contract LucidSwirlTest is Test {
    event SquadCreated(address lider, bytes32 squadId, uint8[10] attributes);
    event MissionCreated(uint8 missionId);
    event MissionJoined(bytes32 squadId, uint8 missionId);
    event MissionStarted(uint8 missionId, uint256 requestId);
    event RoundPlayed(uint8 missionId, uint scenaryId, uint8 round);
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);
    event SquadEliminated(uint8 missionId, bytes32 winner);
    event MissionFinished(uint8 missionId, bytes32 winner);
    event RewardClaimed(uint8 missionId, address winner, uint256 amount);

    LinkToken public linkToken;
    MockVRFCoordinatorV2 public vrfCoordinator;
    LucidSwirl public game;
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
        game = new LucidSwirl(
            keyHash,
            address(vrfCoordinator),
            subId,
            [
                [1, 0, 0, 2, 0, 0, 0, 2, 0, 0],
                [2, 0, 1, 2, 0, 0, 1, 2, 0, 0],
                [0, 1, 0, 1, 0, 0, 0, 1, 0, 0],
                [1, 0, 0, 1, 0, 0, 0, 1, 0, 0],
                [0, 0, 0, 2, 0, 0, 0, 0, 0, 0]
            ],
            [
                [0, 2, 0, 0, 1, 0, 0, 0, 1, 2],
                [0, 1, 0, 0, 0, 0, 0, 0, 2, 2],
                [0, 0, 0, 0, 2, 0, 0, 0, 0, 0],
                [0, 2, 0, 0, 1, 0, 0, 0, 1, 1],
                [0, 0, 0, 0, 1, 0, 0, 0, 1, 0]
            ]
        );
        vrfCoordinator.addConsumer(subId, address(game));
    }

    function testCreateMission() public {
        vm.expectEmit(true, true, true, true);
        emit MissionCreated(1);
        game.createMission(1, 8, 0.1 ether, 60);
        (
            address winner,
            uint256 countdown,
            uint256 rewards,
            uint256 fee,
            uint16 countdownDelay,
            uint8 id,
            uint8 minParticipantsPerMission,
            uint8 registered,
            uint8 round,
            LucidSwirl.MissionState state
        ) = game.missions(1);
        assertTrue(winner == address(0));
        assertTrue(id == 1);
        assertTrue(round == 1);
        assertTrue(state == LucidSwirl.MissionState.Ready);
        assertTrue(minParticipantsPerMission == 8);
        assertTrue(countdownDelay == 60);
        assertTrue(countdown == 0);
        assertTrue(registered == 0);
        assertTrue(rewards == 0);
        assertTrue(fee == 0.1 ether);
    }

    function testAlreadyMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 1, 0.1 ether, 60);
        vm.expectRevert(LucidSwirl.AlreadyMission.selector);
        game.createMission(missionId, 1, 0.1 ether, 60);
    }

    function testCreateSquad() public {
        // create squad successfully
        address owner = address(1);
        vm.startPrank(owner);
        (bytes32 squadId, uint8[10] memory attributes) = utils.createSquad(
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
        emit SquadCreated(owner, squadId, attributes);
        game.createSquad(attributes);

        (address payable lider, , ) = game.squads(squadId);
        assertTrue(lider == owner);

        (attributes, ) = game.getSquad(squadId);

        assertTrue(attributes[0] == 8);
        assertTrue(attributes[1] == 5);
        assertTrue(attributes[2] == 3);
        assertTrue(attributes[3] == 7);
        assertTrue(attributes[4] == 1);
        assertTrue(attributes[5] == 9);
        assertTrue(attributes[6] == 3);
        assertTrue(attributes[7] == 10);
        assertTrue(attributes[8] == 2);
        assertTrue(attributes[9] == 2);

        // should revert if squad already exists
        vm.expectRevert(LucidSwirl.SquadAlreadyExist.selector);
        game.createSquad(attributes);

        // should revert if attributes are invalid
        (, uint8[10] memory invalidAttribute) = utils.createSquad(
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

        vm.expectRevert(LucidSwirl.InvalidAttribute.selector);
        game.createSquad(invalidAttribute);

        // should revert if attributes are invalid, the sum of attributes should be 50
        (, uint8[10] memory invalidAttributes) = utils.createSquad(
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
        vm.expectRevert(LucidSwirl.AttributesSumNot50.selector);
        game.createSquad(invalidAttributes);

        vm.stopPrank();
    }

    function testJoinMission() public {
        uint8 missionId = 1;
        game.createMission(missionId, 5, 0.1 ether, 60);

        address alice = address(2);
        utils.fundSpecificAddress(alice);

        vm.startPrank(alice);
        (bytes32 squadId, uint8[10] memory attributes) = utils.createSquad(
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
        emit MissionJoined(squadId, missionId);
        game.joinMission{value: 0.1 ether}(squadId, missionId);
        vm.stopPrank();

        // should revert if squad is not the leader
        address bob = address(3);
        utils.fundSpecificAddress(bob);
        vm.startPrank(bob);
        (, uint8[10] memory attributes1) = utils.createSquad(
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
        vm.expectRevert(LucidSwirl.NotALider.selector);
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
        game.createMission(missionId, 5, 0.1 ether, 60);

        Utilities.SquadInfo[] memory players = new Utilities.SquadInfo[](5);
        players[0] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 7, 1, 9, 3, 10, 2, 2],
            address(10)
        );
        players[1] = utils.createAndSetupSquadInfo(
            [6, 7, 3, 7, 1, 9, 3, 10, 2, 2],
            address(11)
        );
        players[2] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 5, 2, 9, 3, 10, 3, 2],
            address(12)
        );
        players[3] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 7, 3, 9, 3, 5, 2, 5],
            address(13)
        );
        players[4] = utils.createAndSetupSquadInfo(
            [7, 4, 2, 6, 1, 7, 3, 10, 6, 4],
            address(14)
        );

        joinMission(players, missionId);
        game.startMission(missionId);

        // should start after countdown is over and mission is ready
        uint8 anotherMissionId = 2;
        game.createMission(anotherMissionId, 1, 0.2 ether, 3600);

        Utilities.SquadInfo memory player5 = utils.createAndSetupSquadInfo(
            [8, 4, 2, 6, 1, 7, 3, 10, 6, 3],
            address(15)
        );
        vm.startPrank(player5.lider);
        utils.fundSpecificAddress(player5.lider);
        game.createSquad(player5.attributes);
        game.joinMission{value: 0.2 ether}(player5.squadId, anotherMissionId);
        (, , LucidSwirl.SquadState squadInfoState) = game.squads(
            player5.squadId
        );
        assertTrue(squadInfoState == LucidSwirl.SquadState.Ready);
        vm.stopPrank();

        (, , , , , , , , , LucidSwirl.MissionState state) = game.missions(
            anotherMissionId
        );
        assertTrue(state == LucidSwirl.MissionState.Ready);

        // should revert if the squad is playing in another mission
        vm.expectRevert(LucidSwirl.SquadInMission.selector);
        vm.startPrank(players[0].lider);
        game.joinMission{value: 0.2 ether}(
            players[0].squadId,
            anotherMissionId
        );

        vm.warp(block.timestamp + 3600);

        Utilities.SquadInfo memory player6 = utils.createAndSetupSquadInfo(
            [7, 8, 2, 6, 1, 7, 3, 10, 2, 4],
            address(16)
        );
        vm.startPrank(player6.lider);
        utils.fundSpecificAddress(player6.lider);
        game.createSquad(player6.attributes);

        game.joinMission{value: 0.2 ether}(player6.squadId, anotherMissionId);
        (, , LucidSwirl.SquadState squadInfoState1) = game.squads(
            player6.squadId
        );
        assertTrue(squadInfoState1 == LucidSwirl.SquadState.InMission);
        vm.stopPrank();

        (, , , , , , , , , LucidSwirl.MissionState state1) = game.missions(
            anotherMissionId
        );
        assertTrue(state1 == LucidSwirl.MissionState.InProgress);

        (, , squadInfoState) = game.squads(player5.squadId);
        assertTrue(squadInfoState == LucidSwirl.SquadState.InMission);

        (, , squadInfoState1) = game.squads(player6.squadId);
        assertTrue(squadInfoState1 == LucidSwirl.SquadState.InMission);

        // should revert if squad is not the leader
        // should revert if the mission is not ready
        // should revert if squad is not formed
        // should revert if payment is not enough
    }

    function testFinishMission() public {
        vm.pauseGasMetering();
        uint8 missionId = 1;
        game.createMission(missionId, 5, 0.1 ether, 60);

        Utilities.SquadInfo[] memory players = new Utilities.SquadInfo[](5);
        players[0] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 7, 1, 9, 3, 10, 2, 2],
            address(10)
        );
        players[1] = utils.createAndSetupSquadInfo(
            [6, 7, 3, 7, 1, 9, 3, 10, 2, 2],
            address(11)
        );
        players[2] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 5, 2, 9, 3, 10, 3, 2],
            address(12)
        );
        players[3] = utils.createAndSetupSquadInfo(
            [8, 5, 3, 7, 3, 9, 3, 5, 2, 5],
            address(13)
        );
        players[4] = utils.createAndSetupSquadInfo(
            [7, 4, 2, 6, 1, 7, 3, 10, 6, 4],
            address(14)
        );

        joinMission(players, missionId);

        game.startMission(missionId);

        uint256 requestId = 1;
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        requestId = 2;
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        requestId = 3;
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        requestId = 4;
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        requestId = 5;
        vm.expectEmit(true, true, true, true);
        emit SquadEliminated(missionId, players[4].squadId);
        emit SquadEliminated(missionId, players[3].squadId);
        emit SquadEliminated(missionId, players[2].squadId);
        emit SquadEliminated(missionId, players[1].squadId);
        emit MissionFinished(missionId, players[0].squadId);
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        vm.startPrank(players[0].lider);
        vm.expectEmit(true, true, true, true);
        emit RewardClaimed(missionId, players[0].lider, 0.5 ether);
        game.claimReward(missionId);
        vm.stopPrank();
    }

    function checkWords(uint256 requestId) private {
        uint256[] memory words = utils.getWords(
            requestId,
            game.NUMWORDS() - 1,
            10
        );
        (uint8[] memory randomness, ) = game.getRequest(requestId);
        for (uint8 i = 0; i < randomness.length; i++) {
            assertTrue(randomness[i] == words[i]);
        }
    }

    function joinMission(
        Utilities.SquadInfo[] memory players,
        uint8 missionId
    ) private {
        for (uint8 i = 0; i < players.length; i++) {
            vm.startPrank(players[i].lider);
            utils.fundSpecificAddress(players[i].lider);

            game.createSquad(players[i].attributes);
            game.joinMission{value: 0.1 ether}(players[i].squadId, missionId);
            vm.stopPrank();
        }
    }
}
