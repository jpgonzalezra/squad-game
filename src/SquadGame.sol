// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Owned} from "@solmate/auth/Owned.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "forge-std/console.sol";

/**
 * @title
 * @author jpgonzalezra
 * @notice
 *
 */
contract SquadGame is VRFConsumerBaseV2, Owned {
    VRFCoordinatorV2Interface immutable COORDINATOR;

    // events
    event SquadCreated(bytes32 squadId, uint8[10] attributes);
    event MissionCreated(uint8 missionId);
    event MissionJoined(bytes32 squadId, uint8 missionId);
    event MissionStarted(uint8 missionId, uint256 requestId);
    event MissionFinished(uint8 missionId, bytes32[] winners);
    event RoundPlayed(uint8 missionId, uint8 round);
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
    error InvalidOperation();

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

    uint32 private constant ATTR_COUNT = 10;

    // mapping storage
    mapping(address => mapping(bytes32 => bool)) public squadIdsByLider;
    mapping(uint8 => mapping(bytes32 => SquadState))
        public squadStateByMissionId;
    mapping(bytes32 => uint8[10]) public squads;
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

        _verifyScenaries(_incrementModifiers, _decrementModifiers);
        incrementModifiers = _incrementModifiers;
        decrementModifiers = _decrementModifiers;
    }

    /// @notice Create a squad team with the given attributes.
    /// @param _attributes Attributes of the squad team.
    function createSquad(uint8[ATTR_COUNT] calldata _attributes) external {
        bytes32 squadId = keccak256(abi.encodePacked(_attributes));
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            if (squads[squadId][i] != 0) {
                revert SquadAlreadyExist();
            }
        }
        _verifyAttributes(_attributes);

        squadIdsByLider[msg.sender][squadId] = true;
        squads[squadId] = _attributes;

        emit SquadCreated(squadId, _attributes);
    }

    function createLocation() external onlyOwner {}

    /// @notice Create a mission with the given id.
    /// @param missionId Id of the mission.
    function createMission(
        uint8 missionId,
        uint8 minParticipants,
        uint256 fee,
        uint16 countdownDelay
    ) external onlyOwner {
        if (missionId == 0) {
            revert InvalidMissionId();
        }
        if (missionInfoByMissionId[missionId].state != MissionState.NotReady) {
            revert AlreadyMission();
        }
        if (countdownDelay > 604800) {
            revert InvalidCountdownDelay();
        }
        // if (minParticipants < 4) {
        //     revert InvalidMinParticipants();
        // }

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

    /// @notice Play a Round if the mission is over, pays the winners following the received.
    function playRound(uint8 missionId, uint256 requestId) internal {
        bytes32[] memory squadIds = squadIdsByMission[missionId];

        uint8[] memory randomness = requests[requestId].randomness;

        uint256 scenaryId = requests[requestId].scenaryId;
        uint8[ATTR_COUNT] memory incrementModifier = incrementModifiers[
            scenaryId
        ];
        uint8[ATTR_COUNT] memory decrementModifier = decrementModifiers[
            scenaryId
        ];

        uint256 squadsCount = squadIds.length;

        for (uint i = 0; i < squadsCount; i++) {
            bytes32 squadId = squadIds[i];
            uint8[ATTR_COUNT] memory squadAttr = squads[squadId];
            for (uint j = 0; j < ATTR_COUNT; j++) {
                squadAttr[j] -= incrementModifier[j];
                squadAttr[j] += decrementModifier[j];

                if (randomness[j] > squadAttr[j]) {
                    // health -= 1
                    // if (health == 0){
                    //     removeSquadIdFromMission(missionId, squadId);
                    // }
                }
            }
        }

        Mission memory mission = missionInfoByMissionId[missionId];
        // remove squadId for the mission (squadIdsByMission)
        // if squadIdsByMission is one or empty, then the mission is completed
        // if (squadsCount <= 1) {
        //     removeSqaudIdFromMission(missionId);
        //     missionInfoByMissionId[missionId].state = MissionState.Completed;
        // }
        // dejar todo preparado para que los ganadores hagan el claim
        emit RoundPlayed(missionId, mission.round);

        //or
        if (squadIdsByMission[missionId].length == 1) {
            delete squadIdsByMission[missionId];
            missionInfoByMissionId[missionId].state = MissionState.Completed;
            emit MissionFinished(missionId, squadIdsByMission[missionId]);
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
        requests[requestId].scenary = uint8(
            randomWords[ATTR_COUNT] % incrementModifiers.length
        );
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            requests[requestId].randomness[i] = uint8(
                randomWords[i] % (ATTR_COUNT + 1)
            );
        }
        emit RandomnessReceived(requestId, requests[requestId].randomness);
        playRound(requests[requestId].missionId, requestId);
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

    function _verifyAttributes(
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

    function _verifyScenaries(
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

    function getRequest(
        uint256 missionId
    ) public view returns (uint8[] memory, uint8, uint8) {
        ChainLinkRequest memory request = requests[missionId];
        return (request.randomness, request.scenary, request.missionId);
    }

    function removeSquadIdFromMission(
        uint8 missionId,
        bytes32 squadId
    ) internal {
        bytes32[] storage squadIds = squadIdsByMission[missionId];
        if (squadIds.length == 1) {
            revert InvalidOperation();
        }

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
    }
}
