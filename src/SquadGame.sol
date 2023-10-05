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
    event JoinedMission(bytes32 squadId, uint8 missionId);
    event StartedMission(uint8 missionId, uint256 requestId);
    event FinishedMission(uint8 missionId);
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);

    // chainlink constants and storage
    uint32 private constant CALLBACK_GASLIMIT = 200_000; // The gas limit for the random number callback
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // The number of blocks confirmed before the request is

    // considered fulfilled
    uint32 public constant NUMWORDS = 1; // The number of random words to request

    bytes32 private immutable vrfKeyHash; // The key hash for the VRF request
    uint64 private immutable vrfSubscriptionId; // The subscription ID for the VRF request

    struct ChainLinkRequest {
        uint256 randomness;
        uint8 missionId;
    }

    // miscellaneous constants
    uint256 public participationFee = 0.1 ether;

    error InvalidAttribute();
    error AttributesSumNot50();
    error SquadIsNotFormed();
    error SquadAlreadyExist();
    error SquadNotFormed();
    error SquadNotReady();
    error MissionNotReady();
    error NotEnoughParticipants();
    error UpgradeFeeNotMet();
    error NotALider();
    error AlreadyMission();
    error ParticipationFeeNotEnough();
    error InvalidMissionId();

    // external factors stagorage
    // struct Scenary {

    // }

    // Scenary[] public scenarios;

    // squad storage
    struct Squad {
        uint8[10] attributes;
        SquadState state;
    }

    enum SquadState {
        Unformed, // The squad has not yet been formed
        Formed, // The squad has been formed but is not ready for the mission
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
        uint8 id;
        uint8 minParticipantsPerMission;
        MissionState state;
    }

    // mapping storage
    mapping(address => mapping(bytes32 => bool)) public squadIdsByLider;
    mapping(bytes32 => Squad) public squadInfoBySquadId;
    mapping(uint8 => uint256) public rewardsByMission;
    mapping(uint8 => bytes32[]) public squadIdsByMission;
    mapping(uint8 => Mission) public missionInfoByMissionId;
    mapping(uint256 => ChainLinkRequest) public requests;

    modifier onlyLider(bytes32 squadId) {
        if (!squadIdsByLider[msg.sender][squadId]) {
            revert NotALider();
        }
        _;
    }

    constructor(
        bytes32 _vrfKeyHash,
        address _vrfCoordinator,
        uint64 _vrfSubscriptionId
    ) Owned(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        // chainlink configuration
        vrfKeyHash = _vrfKeyHash;
        vrfSubscriptionId = _vrfSubscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);

        // external factors configuration
        // TODO:
    }

    /// @notice Create a squad team with the given attributes.
    /// @param _attributes Attributes of the squad team.
    function createSquad(uint8[10] calldata _attributes) external {
        bytes32 squadId = keccak256(abi.encodePacked(_attributes));
        if (squadInfoBySquadId[squadId].state != SquadState.Unformed) {
            revert SquadAlreadyExist();
        }
        _verifyAttributes(_attributes);

        squadIdsByLider[msg.sender][squadId] = true;
        squadInfoBySquadId[squadId] = Squad({
            attributes: _attributes,
            state: SquadState.Formed
        });

        emit SquadCreated(squadId, _attributes);
    }

    function createLocation() external onlyOwner {}

    /// @notice Create a mission with the given id.
    /// @param missionId Id of the mission.
    function createMission(
        uint8 missionId,
        uint8 minParticipants
    ) external onlyOwner {
        if (missionId == 0) {
            revert InvalidMissionId();
        }
        if (missionInfoByMissionId[missionId].state != MissionState.NotReady) {
            revert AlreadyMission();
        }
        missionInfoByMissionId[missionId] = Mission({
            id: missionId,
            minParticipantsPerMission: minParticipants,
            state: MissionState.Ready
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
        if (missionInfoByMissionId[missionId].state != MissionState.Ready) {
            revert MissionNotReady();
        }
        if (squadInfoBySquadId[squadId].state != SquadState.Formed) {
            revert SquadNotFormed();
        }
        if (msg.value < participationFee) {
            revert ParticipationFeeNotEnough();
        }
        // if(participantes == minpar y la secino no arranco) {
        //     startTime = block.timestamp;
        // }
        // if (startTime + 1 days < block.timestamp) {
        //     startGAme
        // }

        rewardsByMission[missionId] += msg.value;

        squadIdsByMission[missionId].push(squadId);
        squadInfoBySquadId[squadId].state = SquadState.Ready;

        emit JoinedMission(squadId, missionId);
    }

    /// @notice Execute the run when it is full.
    function startMission(uint8 missionId) external onlyOwner {
        if (
            squadIdsByMission[missionId].length <
            missionInfoByMissionId[missionId].minParticipantsPerMission
        ) {
            revert NotEnoughParticipants();
        }

        bytes32[] memory squadIds = squadIdsByMission[missionId];
        uint256 squadIdsLenth = squadIds.length;
        for (uint256 i = 0; i < squadIdsLenth; i++) {
            if (squadInfoBySquadId[squadIds[i]].state != SquadState.Ready) {
                revert SquadNotReady();
            }
            squadInfoBySquadId[squadIds[i]].state = SquadState.InMission;
        }

        uint256 requestId = requestRandomness();
        requests[requestId] = ChainLinkRequest({
            missionId: missionId,
            randomness: 0
        });

        emit StartedMission(missionId, requestId);
    }

    /// @notice Finishes the mission and pays the winners following the received.
    function finishMission(uint8 missionId, uint256 requestId) internal {
        // matematica
        // dividir los premio  entre los 3 primeros
        // dejar todo preparado para que los ganadores hagan el claim
        emit FinishedMission(missionId);
    }

    /// @notice Callback function used by the VRF Coordinator to return the random number
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        requests[requestId].randomness = randomWords[0];
        if (requests[requestId].missionId == 0) {
            revert InvalidMissionId();
        }
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

    function _verifyAttributes(uint8[10] calldata _attributes) internal pure {
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

    function getSquadInfoBySquadId(
        bytes32 squadId
    ) public view returns (uint8[10] memory, SquadState) {
        Squad memory squad = squadInfoBySquadId[squadId];
        return (squad.attributes, squad.state);
    }
}
