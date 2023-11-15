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
    event HostCreated(address pass, bytes32 hostId, uint8[10] attributes);
    event SpiralCreated(uint8 spiralId);
    event SpiralJoined(bytes32 hostId, uint8 spiralId);
    event SpiralStarted(uint8 spiralId, uint256 requestId);
    event TaikoPlayed(uint8 spiralId, uint xerealId, uint8 taiko);
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);
    event HostEliminated(uint8 spiralId, bytes32 survivor);
    event SpiralFinished(uint8 spiralId, bytes32 survivor);
    event RewardClaimed(uint8 spiralId, address survivor, uint256 amount);

    LinkToken public linkToken;
    MockVRFCoordinatorV2 public vrfCoordinator;
    LucidSwirl public game;
    Utilities internal utils;

    uint96 constant FUND_AMOUNT = 1 * 10 ** 18;

    // Initialized as blank, fine for testing
    uint64 subId;
    bytes32 keyHash; // gasLane

    event ReturnedTabaroth(uint256[] randomWords);

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

    function testCreateSpiral() public {
        vm.expectEmit(true, true, true, true);
        emit SpiralCreated(1);
        game.createSpiral(1, 8, 0.1 ether, 60);
        (
            address survivor,
            uint256 countdown,
            uint256 rewards,
            uint256 fee,
            uint16 countdownDelay,
            uint8 id,
            uint8 minHostsPerSpiral,
            uint8 registered,
            uint8 taiko,
            LucidSwirl.SpiralState state
        ) = game.spirals(1);
        assertTrue(survivor == address(0));
        assertTrue(id == 1);
        assertTrue(taiko == 1);
        assertTrue(state == LucidSwirl.SpiralState.Ready);
        assertTrue(minHostsPerSpiral == 8);
        assertTrue(countdownDelay == 60);
        assertTrue(countdown == 0);
        assertTrue(registered == 0);
        assertTrue(rewards == 0);
        assertTrue(fee == 0.1 ether);
    }

    function testAlreadySpiral() public {
        uint8 spiralId = 1;
        game.createSpiral(spiralId, 1, 0.1 ether, 60);
        vm.expectRevert(LucidSwirl.AlreadySpiral.selector);
        game.createSpiral(spiralId, 1, 0.1 ether, 60);
    }

    function testCreateHost() public {
        // create host successfully
        address owner = address(1);
        vm.startPrank(owner);
        (bytes32 hostId, uint8[10] memory attributes) = utils.createHost(
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
        emit HostCreated(owner, hostId, attributes);
        game.createHost(attributes);

        (address payable pass, , ) = game.hosts(hostId);
        assertTrue(pass == owner);

        (attributes, ) = game.getHost(hostId);

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

        // should revert if host already exists
        vm.expectRevert(LucidSwirl.HostAlreadyExist.selector);
        game.createHost(attributes);

        // should revert if attributes are invalid
        (, uint8[10] memory invalidAttribute) = utils.createHost(
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
        game.createHost(invalidAttribute);

        // should revert if attributes are invalid, the sum of attributes should be 50
        (, uint8[10] memory invalidAttributes) = utils.createHost(
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
        game.createHost(invalidAttributes);

        vm.stopPrank();
    }

    function testJoinSpiral() public {
        uint8 spiralId = 1;
        game.createSpiral(spiralId, 5, 0.1 ether, 60);

        address alice = address(2);
        utils.fundSpecificAddress(alice);

        vm.startPrank(alice);
        (bytes32 hostId, uint8[10] memory attributes) = utils.createHost(
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
        game.createHost(attributes);

        vm.expectEmit(true, true, true, true);
        emit SpiralJoined(hostId, spiralId);
        game.joinSpiral{value: 0.1 ether}(hostId, spiralId);
        vm.stopPrank();

        // should revert if host is not the pass
        address bob = address(3);
        utils.fundSpecificAddress(bob);
        vm.startPrank(bob);
        (, uint8[10] memory attributes1) = utils.createHost(
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
        game.createHost(attributes1);

        vm.stopPrank();
        vm.expectRevert(LucidSwirl.NotAHost.selector);
        game.joinSpiral{value: 0.1 ether}(hostId, spiralId);

        // should revert if the spiral is not ready
        // TODO:

        // should revert if host is not formed
        // TODO:

        // should revert if payment is not enough
        // TODO:
    }

    function testStartSpiral() public {
        uint8 spiralId = 1;
        game.createSpiral(spiralId, 5, 0.1 ether, 60);

        Utilities.HostInfo[] memory players = new Utilities.HostInfo[](5);
        players[0] = utils.createAndSetupHostInfo(
            [8, 5, 3, 7, 1, 9, 3, 10, 2, 2],
            address(10)
        );
        players[1] = utils.createAndSetupHostInfo(
            [6, 7, 3, 7, 1, 9, 3, 10, 2, 2],
            address(11)
        );
        players[2] = utils.createAndSetupHostInfo(
            [8, 5, 3, 5, 2, 9, 3, 10, 3, 2],
            address(12)
        );
        players[3] = utils.createAndSetupHostInfo(
            [8, 5, 3, 7, 3, 9, 3, 5, 2, 5],
            address(13)
        );
        players[4] = utils.createAndSetupHostInfo(
            [7, 4, 2, 6, 1, 7, 3, 10, 6, 4],
            address(14)
        );

        joinSpiral(players, spiralId);
        game.startSpiral(spiralId);

        // should start after countdown is over and spiral is ready
        uint8 anotherSpiralId = 2;
        game.createSpiral(anotherSpiralId, 1, 0.2 ether, 3600);

        Utilities.HostInfo memory player5 = utils.createAndSetupHostInfo(
            [8, 4, 2, 6, 1, 7, 3, 10, 6, 3],
            address(15)
        );
        vm.startPrank(player5.pass);
        utils.fundSpecificAddress(player5.pass);
        game.createHost(player5.attributes);
        game.joinSpiral{value: 0.2 ether}(player5.hostId, anotherSpiralId);
        (, , LucidSwirl.HostState hostInfoState) = game.hosts(
            player5.hostId
        );
        assertTrue(hostInfoState == LucidSwirl.HostState.Ready);
        vm.stopPrank();

        (, , , , , , , , , LucidSwirl.SpiralState state) = game.spirals(
            anotherSpiralId
        );
        assertTrue(state == LucidSwirl.SpiralState.Ready);

        // should revert if the host is playing in another spiral
        vm.expectRevert(LucidSwirl.HostInSpiral.selector);
        vm.startPrank(players[0].pass);
        game.joinSpiral{value: 0.2 ether}(
            players[0].hostId,
            anotherSpiralId
        );

        vm.warp(block.timestamp + 3600);

        Utilities.HostInfo memory player6 = utils.createAndSetupHostInfo(
            [7, 8, 2, 6, 1, 7, 3, 10, 2, 4],
            address(16)
        );
        vm.startPrank(player6.pass);
        utils.fundSpecificAddress(player6.pass);
        game.createHost(player6.attributes);

        game.joinSpiral{value: 0.2 ether}(player6.hostId, anotherSpiralId);
        (, , LucidSwirl.HostState hostInfoState1) = game.hosts(
            player6.hostId
        );
        assertTrue(hostInfoState1 == LucidSwirl.HostState.InSpiral);
        vm.stopPrank();

        (, , , , , , , , , LucidSwirl.SpiralState state1) = game.spirals(
            anotherSpiralId
        );
        assertTrue(state1 == LucidSwirl.SpiralState.InProgress);

        (, , hostInfoState) = game.hosts(player5.hostId);
        assertTrue(hostInfoState == LucidSwirl.HostState.InSpiral);

        (, , hostInfoState1) = game.hosts(player6.hostId);
        assertTrue(hostInfoState1 == LucidSwirl.HostState.InSpiral);

        // should revert if host is not the pass
        // should revert if the spiral is not ready
        // should revert if host is not formed
        // should revert if payment is not enough
    }

    function testFinishSpiral() public {
        vm.pauseGasMetering();
        uint8 spiralId = 1;
        game.createSpiral(spiralId, 5, 0.1 ether, 60);

        Utilities.HostInfo[] memory players = new Utilities.HostInfo[](5);
        players[0] = utils.createAndSetupHostInfo(
            [8, 5, 3, 7, 1, 9, 3, 10, 2, 2],
            address(10)
        );
        players[1] = utils.createAndSetupHostInfo(
            [6, 7, 3, 7, 1, 9, 3, 10, 2, 2],
            address(11)
        );
        players[2] = utils.createAndSetupHostInfo(
            [8, 5, 3, 5, 2, 9, 3, 10, 3, 2],
            address(12)
        );
        players[3] = utils.createAndSetupHostInfo(
            [8, 5, 3, 7, 3, 9, 3, 5, 2, 5],
            address(13)
        );
        players[4] = utils.createAndSetupHostInfo(
            [7, 4, 2, 6, 1, 7, 3, 10, 6, 4],
            address(14)
        );

        joinSpiral(players, spiralId);

        game.startSpiral(spiralId);

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
        emit HostEliminated(spiralId, players[4].hostId);
        emit HostEliminated(spiralId, players[3].hostId);
        emit HostEliminated(spiralId, players[2].hostId);
        emit HostEliminated(spiralId, players[1].hostId);
        emit SpiralFinished(spiralId, players[0].hostId);
        vrfCoordinator.fulfillRandomWords(requestId, address(game));
        checkWords(requestId);

        vm.startPrank(players[0].pass);
        vm.expectEmit(true, true, true, true);
        emit RewardClaimed(spiralId, players[0].pass, 0.5 ether);
        game.claimReward(spiralId);
        vm.stopPrank();
    }

    function checkWords(uint256 requestId) private {
        uint256[] memory words = utils.getWords(
            requestId,
            game.NUMWORDS() - 1,
            10
        );
        (uint8[] memory tabaroth, ) = game.getRequest(requestId);
        for (uint8 i = 0; i < tabaroth.length; i++) {
            assertTrue(tabaroth[i] == words[i]);
        }
    }

    function joinSpiral(
        Utilities.HostInfo[] memory players,
        uint8 spiralId
    ) private {
        for (uint8 i = 0; i < players.length; i++) {
            vm.startPrank(players[i].pass);
            utils.fundSpecificAddress(players[i].pass);

            game.createHost(players[i].attributes);
            game.joinSpiral{value: 0.1 ether}(players[i].hostId, spiralId);
            vm.stopPrank();
        }
    }
}
