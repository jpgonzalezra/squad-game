// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Owned} from "@solmate/auth/Owned.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "forge-std/console.sol";

/**
 * @title SquadGame
 * @author jpgonzalezra
 * @notice SquadGame is a game where you can create a squad team and join a mission to fight against other squads.
 *
 */
contract SquadGame is VRFConsumerBaseV2, Owned {
    VRFCoordinatorV2Interface immutable COORDINATOR;

    // events
    event SquadCreated(address lider, bytes32 squadId, uint8[10] attributes);
    event SquadEliminated(uint8 missionId, bytes32 squadId);
    event MissionCreated(uint8 missionId);
    event MissionJoined(bytes32 squadId, uint8 missionId);
    event MissionStarted(uint8 missionId, uint256 requestId);
    event MissionFinished(uint8 missionId, bytes32 winner);
    event RoundPlayed(uint8 missionId, uint8 scenaryId, uint8 round);
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);
    event RandomnessReceived(uint256 indexed requestId, uint8[] randomness);

    // chainlink constants and storage
    uint32 private constant CALLBACK_GASLIMIT = 200_000; // The gas limit for the random number callback
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // The number of blocks confirmed before the request is

    // considered fulfilled
    uint32 public constant NUMWORDS = 11; // The number of random words to request, pos 11 => scenario

    bytes32 private immutable vrfKeyHash; // The key hash for the VRF request
    uint64 private immutable vrfSubscriptionId; // The subscription ID for the VRF request

    struct ChainLinkRequest {
        uint8 scenaryId;
        uint8 missionId;
        uint8[] randomness;
    }

    // miscellaneous constants
    error InvalidAttribute();
    error InvalidScenary();
    error InvalidScenaries();
    error AttributesSumNot50();
    error SquadIsNotFormed();
    error SquadAlreadyExist();
    error SquadNotReady();
    error JoinMissionFailed();
    error MissionNotReady();
    error AlreadyMission();
    error InvalidMissionId();
    error InvalidCountdownDelay();
    error NotEnoughParticipants();
    error UpgradeFeeNotMet();
    error NotALider();
    error ParticipationFeeNotEnough();
    error NotOwnerOrGame();
    error InvalidMinParticipants();

    uint8[10][5] public incrementModifiers;
    uint8[10][5] public decrementModifiers;

    enum SquadState {
        Unformed, // The squad has not yet been formed
        Ready, // The squad is ready for the mission but it has not yet started
        InMission // The squad is currently in a mission
    }

    // mission storage
    enum MissionState {
        NotReady, // Not ready for the mission
        Ready, // Ready for the mission but it has not yet started
        InProgress, // The mission is in progress
        Completed // The mission has been completed
    }

    struct Mission {
        uint256 countdown;
        uint256 rewards;
        uint256 fee;
        uint16 countdownDelay; // 7 days as max countdown
        uint8 id;
        uint8 minParticipantsPerMission;
        uint8 registered;
        uint8 round;
        MissionState state;
    }

    struct Squad {
        uint8 health;
        uint8[10] attributes;
    }

    uint32 private constant ATTR_COUNT = 10;

    // mapping storage
    mapping(address => mapping(bytes32 => bool)) public squadIdsByLider;
    mapping(uint8 => mapping(bytes32 => SquadState))
        public squadStateByMissionId;
    mapping(bytes32 => Squad) public squads;
    mapping(uint8 => bytes32[]) public squadIdsByMission;
    mapping(uint8 => Mission) public missionInfoByMissionId;
    mapping(uint256 => ChainLinkRequest) private requests;

    modifier onlyOwnerOrGame() {
        if (msg.sender != owner && msg.sender != address(this)) {
            revert NotOwnerOrGame();
        }
        _;
    }
    modifier onlyLider(bytes32 squadId) {
        if (!squadIdsByLider[msg.sender][squadId]) {
            revert NotALider();
        }
        _;
    }

    constructor(
        bytes32 _vrfKeyHash,
        address _vrfCoordinator,
        uint64 _vrfSubscriptionId,
        uint8[ATTR_COUNT][5] memory _incrementModifiers,
        uint8[ATTR_COUNT][5] memory _decrementModifiers
    ) Owned(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        // chainlink configuration
        vrfKeyHash = _vrfKeyHash;
        vrfSubscriptionId = _vrfSubscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);

        verifyScenaries(_incrementModifiers, _decrementModifiers);
        incrementModifiers = _incrementModifiers;
        decrementModifiers = _decrementModifiers;
    }

    /// @notice Create a squad team with the given attributes.
    /// @param _attributes Attributes of the squad team.
    function createSquad(uint8[ATTR_COUNT] calldata _attributes) external {
        // If any mission is in a position to play a round, execute it regardless

        bytes32 squadId = keccak256(abi.encodePacked(_attributes));
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            if (squads[squadId].health != 0) {
                revert SquadAlreadyExist();
            }
        }
        verifyAttributes(_attributes);

        squadIdsByLider[msg.sender][squadId] = true;
        squads[squadId] = Squad({health: 20, attributes: _attributes});

        emit SquadCreated(msg.sender, squadId, _attributes);
    }

    /// @notice Create a mission with the given id.
    /// @param missionId Id of the mission.
    function createMission(
        uint8 missionId,
        uint8 minParticipants,
        uint256 fee,
        uint16 countdownDelay
    ) external onlyOwner {
        // If any mission is in a position to play a round, execute it regardless

        if (missionId == 0) {
            revert InvalidMissionId();
        }
        if (missionInfoByMissionId[missionId].state != MissionState.NotReady) {
            revert AlreadyMission();
        }
        if (countdownDelay > 604800) {
            revert InvalidCountdownDelay();
        }

        missionInfoByMissionId[missionId] = Mission({
            id: missionId,
            minParticipantsPerMission: minParticipants,
            state: MissionState.Ready,
            fee: fee,
            registered: 0,
            countdown: 0,
            rewards: 0,
            round: 0,
            countdownDelay: countdownDelay
        });
        emit MissionCreated(missionId);
    }

    /// @notice Join the queue for the upcoming mission.
    /// @param squadId Id of the squad team.
    /// @param missionId Id of the mission.
    function joinMission(
        bytes32 squadId,
        uint8 missionId
    ) external payable onlyLider(squadId) {
        // If any mission is in a position to play a round, execute it regardless

        Mission memory mission = missionInfoByMissionId[missionId];
        if (mission.state != MissionState.Ready) {
            revert MissionNotReady();
        }
        if (squadStateByMissionId[missionId][squadId] != SquadState.Unformed) {
            revert JoinMissionFailed();
        }
        if (msg.value < mission.fee) {
            revert ParticipationFeeNotEnough();
        }
        if (
            mission.minParticipantsPerMission > mission.registered &&
            mission.countdown == 0
        ) {
            missionInfoByMissionId[missionId].countdown = block.timestamp;
        }

        squadStateByMissionId[missionId][squadId] = SquadState.Ready;
        if (block.timestamp >= mission.countdown + mission.countdownDelay) {
            squadStateByMissionId[missionId][squadId] = SquadState.InMission;
            this.startMission(missionId);
        }

        missionInfoByMissionId[missionId].rewards += msg.value;
        missionInfoByMissionId[missionId].registered += 1;

        squadIdsByMission[missionId].push(squadId);

        emit MissionJoined(squadId, missionId);
    }

    /// @notice Execute the run when it is full.
    function startMission(uint8 missionId) public onlyOwnerOrGame {
        if (
            squadIdsByMission[missionId].length <
            missionInfoByMissionId[missionId].minParticipantsPerMission
        ) {
            revert NotEnoughParticipants();
        }

        bytes32[] memory squadIds = squadIdsByMission[missionId];
        uint256 squadIdsLenth = squadIds.length;
        for (uint256 i = 0; i < squadIdsLenth; i++) {
            if (
                squadStateByMissionId[missionId][squadIds[i]] !=
                SquadState.Ready
            ) {
                revert SquadNotReady();
            }
            squadStateByMissionId[missionId][squadIds[i]] = SquadState
                .InMission;
        }

        uint256 requestId = requestRandomness();
        requests[requestId] = ChainLinkRequest({
            scenaryId: 0,
            missionId: missionId,
            randomness: new uint8[](ATTR_COUNT)
        });

        missionInfoByMissionId[missionId].state = MissionState.InProgress;
        emit MissionStarted(missionId, requestId);
    }

    /// @notice Execute the run when it is full.
    function finishMission(uint8 missionId, uint256 requestId) internal {
        bytes32[] storage currentSquadIds = squadIdsByMission[missionId];
        uint8[] memory randomness = requests[requestId].randomness;

        bool finished = false;
        for (uint8 r = 1; !finished; r++) {
            // console.log("--------------------");
            // console.log("Round", r);
            uint8 scenaryId = resolveSceneryId(requestId);
            // console.log("ScenaryId", scenaryId);
            // console.log("--------------------");
            for (uint i = currentSquadIds.length; i > 0 && !finished; i--) {
                bytes32 squadId = currentSquadIds[i - 1];
                // console.log("Team: ", i);
                processSquad(missionId, squadId, scenaryId, randomness);
                if (currentSquadIds.length == 1) {
                    finished = true;
                }
            }

            if (finished) {
                bytes32 winner = currentSquadIds[0];
                delete squadIdsByMission[missionId];
                missionInfoByMissionId[missionId].state = MissionState
                    .Completed;
                emit MissionFinished(missionId, winner);
            } else {
                missionInfoByMissionId[missionId].round = r;
                emit RoundPlayed(
                    missionId,
                    scenaryId,
                    missionInfoByMissionId[missionId].round
                );
            }
        }
    }

    /// @notice Callback function used by the VRF Coordinator to return the random number
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        if (requests[requestId].missionId == 0) {
            revert InvalidMissionId();
        }
        requests[requestId].scenaryId = resolveSceneryId(
            normalizeToRange(
                randomWords[ATTR_COUNT],
                incrementModifiers.length - 1
            )
        );
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            requests[requestId].randomness[i] = normalizeToRange(
                randomWords[i],
                ATTR_COUNT
            );
        }
        emit RandomnessReceived(requestId, requests[requestId].randomness);
        finishMission(requests[requestId].missionId, requestId);
    }

    /// @notice Requests randomness from a user-provided seed
    /// @dev The VRF subscription must be active and sufficient LINK must be available
    /// @return requestId The ID of the request
    function requestRandomness() public returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GASLIMIT,
            NUMWORDS
        );
    }

    function verifyAttributes(
        uint8[ATTR_COUNT] calldata _attributes
    ) internal pure {
        uint8 sum_of_attributes = 0;
        uint256 length = _attributes.length;
        for (uint8 i = 0; i < length; i++) {
            uint8 attr = _attributes[i];
            if (attr <= 0 || attr > 10) {
                revert InvalidAttribute();
            }
            sum_of_attributes += _attributes[i];
        }
        if (sum_of_attributes != 50) {
            revert AttributesSumNot50();
        }
    }

    function verifyScenaries(
        uint8[ATTR_COUNT][5] memory _incrementModifiers,
        uint8[ATTR_COUNT][5] memory _decrementModifiers
    ) internal pure {
        if (_incrementModifiers.length != _decrementModifiers.length) {
            revert InvalidScenaries();
        }
        for (uint256 i = 0; i < _incrementModifiers.length; i++) {
            for (uint256 j = 0; j < 10; j++) {
                if (
                    _incrementModifiers[i][j] > 0 &&
                    _decrementModifiers[i][j] > 0
                ) {
                    revert InvalidScenary();
                }
                if (
                    _incrementModifiers[i][j] > 2 ||
                    _decrementModifiers[i][j] > 2
                ) {
                    revert InvalidScenary();
                }
            }
        }
    }

    function getSquad(
        bytes32 squadId
    ) public view returns (uint8[10] memory, uint8) {
        Squad memory squad = squads[squadId];
        return (squad.attributes, squad.health);
    }

    function getRequest(
        uint256 requestId
    ) public view returns (uint8[] memory, uint8, uint8) {
        ChainLinkRequest memory request = requests[requestId];
        return (
            request.randomness,
            requests[requestId].scenaryId,
            request.missionId
        );
    }

    function removeSquadIdFromMission(
        uint8 missionId,
        bytes32 squadId
    ) internal {
        bytes32[] storage squadIds = squadIdsByMission[missionId];
        uint256 indexToRemove = squadIds.length;
        for (uint256 i = 0; i < squadIds.length; i++) {
            if (squadIds[i] == squadId) {
                indexToRemove = i;
                break;
            }
        }

        if (indexToRemove < squadIds.length) {
            squadIds[indexToRemove] = squadIds[squadIds.length - 1];
            squadIds.pop();
        }
        emit SquadEliminated(missionId, squadId);
    }

    function normalizeToRange(
        uint256 value,
        uint256 maxRange
    ) internal pure returns (uint8) {
        uint256 adjustedRange = maxRange + 1;
        return uint8(value % adjustedRange);
    }

    function adjustAttribute(
        uint8 attribute,
        uint8 increment,
        uint8 decrement
    ) private pure returns (uint8) {
        attribute += increment;
        if (attribute > 10) {
            attribute = 10;
        }

        if (decrement < attribute) {
            attribute -= decrement;
        } else {
            attribute = 0;
        }

        return attribute;
    }

    function processSquad(
        uint8 missionId,
        bytes32 squadId,
        uint8 scenaryId,
        uint8[] memory randomness
    ) internal {
        for (uint j = 0; j < ATTR_COUNT; j++) {
            uint8 adjustedSquadAttr = adjustAttribute(
                squads[squadId].attributes[j],
                incrementModifiers[scenaryId][j],
                decrementModifiers[scenaryId][j]
            );
            if (randomness[j] > adjustedSquadAttr) {
                if (squads[squadId].health > 1) {
                    squads[squadId].health--;
                } else {
                    removeSquadIdFromMission(missionId, squadId);
                    break;
                }
            }
        }
        // console.log("Health: ", squads[squadId].health);
    }

    function resolveSceneryId(
        uint256 requestId
    ) internal returns (uint8 scenaryId) {
        uint8 currentSceneryId = requests[requestId].scenaryId;
        if (currentSceneryId < incrementModifiers.length) {
            requests[requestId].scenaryId += 1;
            return currentSceneryId;
        } else {
            requests[requestId].scenaryId = 0;
            return 0;
        }
    }
}
