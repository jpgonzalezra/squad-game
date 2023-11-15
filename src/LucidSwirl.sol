// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Owned} from "@solmate/auth/Owned.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// import "forge-std/console.sol";

/**
 * @title LucidSwirl
 * @author jpgonzalezra, 0xhermit
 * @notice LucidSwirl is a game where you can create a squad team and join a mission to fight against other squads.
 *
 */
contract LucidSwirl is VRFConsumerBaseV2, Owned {
    VRFCoordinatorV2Interface immutable COORDINATOR;

    // events
    event MissionFinished(uint8 missionId, bytes32 winner);
    event SquadCreated(address lider, bytes32 squadId, uint8[10] attributes);
    event SquadEliminated(uint8 missionId, bytes32 squadId);
    event MissionCreated(uint8 missionId);
    event MissionJoined(bytes32 squadId, uint8 missionId);
    event MissionStarted(uint8 missionId, uint256 requestId);
    event RoundPlayed(
        uint8 missionId,
        uint24 scenaryId,
        uint8 round,
        uint256 nextRequestId
    );
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);
    event RandomnessReceived(uint256 indexed requestId, uint8[] randomness);
    event RewardClaimed(uint8 missionId, address winner, uint256 amount);

    // chainlink constants and storage
    uint32 private constant CALLBACK_GASLIMIT = 200_000; // The gas limit for the random number callback

    // considered fulfilled
    uint32 public constant NUMWORDS = 11; // The number of random words to request, pos 11 => scenario

    bytes32 private immutable vrfKeyHash; // The key hash for the VRF request
    uint64 private immutable vrfSubscriptionId; // The subscription ID for the VRF request

    struct ChainLinkRequest {
        uint8 missionId;
        uint8[] randomness;
        uint8 scenaryId;
    }

    // miscellaneous constants
    error InvalidAttribute();
    error InvalidScenary();
    error InvalidScenaries();
    error AttributesSumNot50();
    error SquadIsNotFormed();
    error SquadAlreadyExist();
    error SquadInMission();
    error SquadNotReady();
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
    error InvalidClaim();
    error RoundNotReady();
    error MissionInProgress();

    uint8[10][5] public incrementModifiers;
    uint8[10][5] public decrementModifiers;

    enum SquadState {
        NotReady, // The squad has not yet been formed
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
        address payable winner;
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
        address payable lider;
        uint8 health;
        SquadState state;
        uint8[10] attributes;
    }

    uint32 private constant ATTR_COUNT = 10;

    // squad id => squad
    mapping(bytes32 => Squad) public squads;
    // mission id => mission
    mapping(uint8 => Mission) public missions;
    // mission id => squad ids
    mapping(uint8 => bytes32[]) public squadIdsByMission;
    // request id => request
    mapping(uint256 => ChainLinkRequest) private requests;

    modifier onlyOwnerOrGame() {
        if (msg.sender != owner && msg.sender != address(this)) {
            revert NotOwnerOrGame();
        }
        _;
    }
    modifier onlyLider(bytes32 squadId) {
        if (squads[squadId].lider != msg.sender) {
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
        bytes32 squadId = keccak256(abi.encodePacked(_attributes));
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            if (squads[squadId].health != 0) {
                revert SquadAlreadyExist();
            }
        }
        verifyAttributes(_attributes);

        squads[squadId] = Squad({
            lider: payable(msg.sender),
            health: 20,
            attributes: _attributes,
            state: SquadState.NotReady
        });

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
        if (missionId == 0) {
            revert InvalidMissionId();
        }
        if (missions[missionId].state != MissionState.NotReady) {
            revert AlreadyMission();
        }
        if (countdownDelay > 604800) {
            revert InvalidCountdownDelay();
        }

        missions[missionId] = Mission({
            winner: payable(address(0)),
            id: missionId,
            minParticipantsPerMission: minParticipants,
            state: MissionState.Ready,
            fee: fee,
            registered: 0,
            countdown: 0,
            rewards: 0,
            round: 1,
            countdownDelay: countdownDelay
        });
        emit MissionCreated(missionId);
    }

    function claimReward(uint8 missionId) external {
        Mission storage mission = missions[missionId];
        if (mission.winner == address(0) || mission.rewards == 0) {
            revert InvalidClaim();
        }

        uint256 rewardsToTransfer = mission.rewards;
        mission.rewards = 0;

        mission.winner.transfer(rewardsToTransfer);
        emit RewardClaimed(missionId, mission.winner, rewardsToTransfer);
    }

    /// @notice Join the queue for the upcoming mission.
    /// @param squadId Id of the squad team.
    /// @param missionId Id of the mission.
    function joinMission(
        bytes32 squadId,
        uint8 missionId
    ) external payable onlyLider(squadId) {
        Mission storage mission = missions[missionId];
        Squad storage squad = squads[squadId];
        if (mission.state != MissionState.Ready) {
            revert MissionNotReady();
        }
        if (squad.state != SquadState.NotReady) {
            revert SquadInMission();
        }
        if (msg.value < mission.fee) {
            revert ParticipationFeeNotEnough();
        }
        if (
            mission.minParticipantsPerMission > mission.registered &&
            mission.countdown == 0
        ) {
            mission.countdown = block.timestamp;
        }

        squad.state = SquadState.Ready;
        if (block.timestamp >= mission.countdown + mission.countdownDelay) {
            squad.state = SquadState.InMission;
            this.startMission(missionId);
        }

        mission.rewards += msg.value;
        mission.registered += 1;

        squadIdsByMission[missionId].push(squadId);

        emit MissionJoined(squadId, missionId);
    }

    /// @notice Execute the run when it is full.
    function startMission(uint8 missionId) public onlyOwnerOrGame {
        if (missions[missionId].state == MissionState.InProgress) {
            revert MissionInProgress();
        }
        if (
            squadIdsByMission[missionId].length <
            missions[missionId].minParticipantsPerMission
        ) {
            revert NotEnoughParticipants();
        }

        bytes32[] memory squadIds = squadIdsByMission[missionId];
        uint256 squadIdsLenth = squadIds.length;

        for (uint256 i = 0; i < squadIdsLenth; i++) {
            if (squads[squadIds[i]].state != SquadState.Ready) {
                revert SquadNotReady();
            }
            squads[squadIds[i]].state = SquadState.InMission;
        }

        uint256 requestId = requestRandomness(3);
        requests[requestId] = ChainLinkRequest({
            scenaryId: 0,
            missionId: missionId,
            randomness: new uint8[](ATTR_COUNT)
        });

        missions[missionId].state = MissionState.InProgress;
        emit MissionStarted(missionId, requestId);
    }

    /// @notice Requests randomness from a user-provided seed
    /// @dev The VRF subscription must be active and sufficient LINK must be available
    /// @return requestId The ID of the request
    function requestRandomness(
        uint16 requestConfirmations
    ) public returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            requestConfirmations,
            CALLBACK_GASLIMIT,
            NUMWORDS
        );
    }

    function getSquad(
        bytes32 squadId
    ) external view returns (uint8[10] memory, uint8) {
        Squad memory squad = squads[squadId];
        return (squad.attributes, squad.health);
    }

    function getRequest(
        uint256 requestId
    ) external view returns (uint8[] memory, uint8) {
        ChainLinkRequest memory request = requests[requestId];
        return (request.randomness, request.missionId);
    }

    /**
     * INTERNAL METHODS
     */

    /// @notice Execute the run when it is full.
    function playRound(uint8 missionId, uint256 requestId) internal {
        Mission storage mission = missions[missionId];

        bytes32[] storage currentSquadIds = squadIdsByMission[missionId];
        uint8[] memory randomness = requests[requestId].randomness;

        uint8 scenaryId = requests[requestId].scenaryId;
        for (uint i = currentSquadIds.length; i > 0; i--) {
            bytes32 squadId = currentSquadIds[i - 1];
            processSquad(missionId, squadId, scenaryId, randomness);

            if (currentSquadIds.length == 1) {
                bytes32 winner = currentSquadIds[0];
                delete squadIdsByMission[missionId];
                mission.state = MissionState.Completed;
                mission.winner = squads[winner].lider;
                squads[squadId].state = SquadState.NotReady;
                emit MissionFinished(missionId, winner);
                return;
            }
        }

        uint16 seconds_per_block_approximately = (mission.countdownDelay *
            mission.round) / 15;
        uint256 nextRequestId = requestRandomness(
            seconds_per_block_approximately
        );
        requests[nextRequestId] = ChainLinkRequest({
            scenaryId: 0,
            missionId: missionId,
            randomness: new uint8[](ATTR_COUNT)
        });

        mission.round += 1;
        emit RoundPlayed(missionId, scenaryId, mission.round, nextRequestId);
    }

    /// @notice Callback function used by the VRF Coordinator to return the random number
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        requests[requestId].scenaryId = uint8(
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
        playRound(requests[requestId].missionId, requestId);
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
    ) internal pure returns (uint8) {
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
        Squad storage squad = squads[squadId];
        for (uint j = 0; j < ATTR_COUNT; j++) {
            uint8 adjustedSquadAttr = adjustAttribute(
                squad.attributes[j],
                incrementModifiers[scenaryId][j],
                decrementModifiers[scenaryId][j]
            );
            if (randomness[j] > adjustedSquadAttr) {
                if (squad.health > 1) {
                    squad.health--;
                } else {
                    removeSquadIdFromMission(missionId, squadId);
                    squad.state = SquadState.NotReady;
                    break;
                }
            }
        }
    }
}