// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Owned} from "@solmate/auth/Owned.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// import "forge-std/console.sol";

/**
 * @title LucidSwirl
 * @author jpgonzalezra, 0xhermit
 * @notice LucidSwirl is a game where you can create a host team and join a spiral to fight against other hosts.
 *
 */
contract LucidSwirl is VRFConsumerBaseV2, Owned {
    VRFCoordinatorV2Interface immutable COORDINATOR;

    // events
    event SpiralFinished(uint8 spiralId, bytes32 winner);
    event HostCreated(address pass, bytes32 hostId, uint8[10] attributes);
    event HostEliminated(uint8 spiralId, bytes32 hostId);
    event SpiralCreated(uint8 spiralId);
    event SpiralJoined(bytes32 hostId, uint8 spiralId);
    event SpiralStarted(uint8 spiralId, uint256 requestId);
    event RoundPlayed(
        uint8 spiralId,
        uint24 scenaryId,
        uint8 round,
        uint256 nextRequestId
    );
    event RequestedLeaderboard(bytes32 indexed requestId, uint256 value);
    event RandomnessReceived(uint256 indexed requestId, uint8[] randomness);
    event RewardClaimed(uint8 spiralId, address winner, uint256 amount);

    // chainlink constants and storage
    uint32 private constant CALLBACK_GASLIMIT = 200_000; // The gas limit for the random number callback

    // considered fulfilled
    uint32 public constant NUMWORDS = 11; // The number of random words to request, pos 11 => scenario

    bytes32 private immutable vrfKeyHash; // The key hash for the VRF request
    uint64 private immutable vrfSubscriptionId; // The subscription ID for the VRF request

    struct ChainLinkRequest {
        uint8 spiralId;
        uint8[] randomness;
        uint8 scenaryId;
    }

    // miscellaneous constants
    error InvalidAttribute();
    error InvalidScenary();
    error InvalidScenaries();
    error AttributesSumNot50();
    error HostIsNotFormed();
    error HostAlreadyExist();
    error HostInSpiral();
    error HostNotReady();
    error SpiralNotReady();
    error AlreadySpiral();
    error InvalidSpiralId();
    error InvalidCountdownDelay();
    error NotEnoughParticipants();
    error UpgradeFeeNotMet();
    error NotALider();
    error ParticipationFeeNotEnough();
    error NotOwnerOrGame();
    error InvalidMinParticipants();
    error InvalidClaim();
    error RoundNotReady();
    error SpiralInProgress();

    uint8[10][5] public incrementModifiers;
    uint8[10][5] public decrementModifiers;

    enum HostState {
        NotReady, // The host has not yet been formed
        Ready, // The host is ready for the spiral but it has not yet started
        InSpiral // The host is currently in a spiral
    }

    // spiral storage
    enum SpiralState {
        NotReady, // Not ready for the spiral
        Ready, // Ready for the spiral but it has not yet started
        InProgress, // The spiral is in progress
        Completed // The spiral has been completed
    }

    struct Spiral {
        address payable winner;
        uint256 countdown;
        uint256 rewards;
        uint256 fee;
        uint16 countdownDelay; // 7 days as max countdown
        uint8 id;
        uint8 minParticipantsPerSpiral;
        uint8 registered;
        uint8 round;
        SpiralState state;
    }

    struct Host {
        address payable pass;
        uint8 health;
        HostState state;
        uint8[10] attributes;
    }
    // attributes:
    // [0] Strength: Determines physical power and ability to carry heavy loads.
    // [1] Endurance: Reflects stamina and resistance to fatigue during prolonged activities.
    // [2] Acrobatics: Influences circus-worthy acrobatics, making the player a nimble ninja in the wilderness.
    // [3] Brainiac: Governs their nerdy intelligence, ability to invent quirky gadgets, and useless trivia knowledge.
    // [4] Perception: Affects awareness, alertness, and the ability to detect subtle details in the environment.
    // [5] Zen-Fu: Represents inner peace and mindfulness, helping the player stay calm in the face of chaotic survival situations.
    // [6] Dexterity: Governs hand-eye coordination, fine motor skills, and overall precision in movement.
    // [7] Charm-o-Meter: Measures the player's charisma, enchanting both humans and woodland creatures alike.
    // [8] Adapt-o-matic: Reflects their shape-shifting skills, turning adversity into opportunities with a dash of humor.
    // [9] Karma: Reflects the player's cosmic balance, influencing the consequences of their actions and the universe's response.

    uint32 private constant ATTR_COUNT = 10;

    // host id => host
    mapping(bytes32 => Host) public hosts;
    // spiral id => spiral
    mapping(uint8 => Spiral) public spirals;
    // spiral id => host ids
    mapping(uint8 => bytes32[]) public hostIdsBySpiral;
    // request id => request
    mapping(uint256 => ChainLinkRequest) private requests;

    modifier onlyOwnerOrGame() {
        if (msg.sender != owner && msg.sender != address(this)) {
            revert NotOwnerOrGame();
        }
        _;
    }
    modifier onlyLider(bytes32 hostId) {
        if (hosts[hostId].pass != msg.sender) {
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

    /// @notice Create a host team with the given attributes.
    /// @param _attributes Attributes of the host team.
    function createHost(uint8[ATTR_COUNT] calldata _attributes) external {
        bytes32 hostId = keccak256(abi.encodePacked(_attributes));
        for (uint256 i = 0; i < ATTR_COUNT; i++) {
            if (hosts[hostId].health != 0) {
                revert HostAlreadyExist();
            }
        }
        verifyAttributes(_attributes);

        hosts[hostId] = Host({
            pass: payable(msg.sender),
            health: 20,
            attributes: _attributes,
            state: HostState.NotReady
        });

        emit HostCreated(msg.sender, hostId, _attributes);
    }

    /// @notice Create a spiral with the given id.
    /// @param spiralId Id of the spiral.
    function createSpiral(
        uint8 spiralId,
        uint8 minParticipants,
        uint256 fee,
        uint16 countdownDelay
    ) external onlyOwner {
        if (spiralId == 0) {
            revert InvalidSpiralId();
        }
        if (spirals[spiralId].state != SpiralState.NotReady) {
            revert AlreadySpiral();
        }
        if (countdownDelay > 604800) {
            revert InvalidCountdownDelay();
        }

        spirals[spiralId] = Spiral({
            winner: payable(address(0)),
            id: spiralId,
            minParticipantsPerSpiral: minParticipants,
            state: SpiralState.Ready,
            fee: fee,
            registered: 0,
            countdown: 0,
            rewards: 0,
            round: 1,
            countdownDelay: countdownDelay
        });
        emit SpiralCreated(spiralId);
    }

    function claimReward(uint8 spiralId) external {
        Spiral storage spiral = spirals[spiralId];
        if (spiral.winner == address(0) || spiral.rewards == 0) {
            revert InvalidClaim();
        }

        uint256 rewardsToTransfer = spiral.rewards;
        spiral.rewards = 0;

        spiral.winner.transfer(rewardsToTransfer);
        emit RewardClaimed(spiralId, spiral.winner, rewardsToTransfer);
    }

    /// @notice Join the queue for the upcoming spiral.
    /// @param hostId Id of the host team.
    /// @param spiralId Id of the spiral.
    function joinSpiral(
        bytes32 hostId,
        uint8 spiralId
    ) external payable onlyLider(hostId) {
        Spiral storage spiral = spirals[spiralId];
        Host storage host = hosts[hostId];
        if (spiral.state != SpiralState.Ready) {
            revert SpiralNotReady();
        }
        if (host.state != HostState.NotReady) {
            revert HostInSpiral();
        }
        if (msg.value < spiral.fee) {
            revert ParticipationFeeNotEnough();
        }
        if (
            spiral.minParticipantsPerSpiral > spiral.registered &&
            spiral.countdown == 0
        ) {
            spiral.countdown = block.timestamp;
        }

        host.state = HostState.Ready;
        if (block.timestamp >= spiral.countdown + spiral.countdownDelay) {
            host.state = HostState.InSpiral;
            this.startSpiral(spiralId);
        }

        spiral.rewards += msg.value;
        spiral.registered += 1;

        hostIdsBySpiral[spiralId].push(hostId);

        emit SpiralJoined(hostId, spiralId);
    }

    /// @notice Execute the run when it is full.
    function startSpiral(uint8 spiralId) public onlyOwnerOrGame {
        if (spirals[spiralId].state == SpiralState.InProgress) {
            revert SpiralInProgress();
        }
        if (
            hostIdsBySpiral[spiralId].length <
            spirals[spiralId].minParticipantsPerSpiral
        ) {
            revert NotEnoughParticipants();
        }

        bytes32[] memory hostIds = hostIdsBySpiral[spiralId];
        uint256 hostIdsLenth = hostIds.length;

        for (uint256 i = 0; i < hostIdsLenth; i++) {
            if (hosts[hostIds[i]].state != HostState.Ready) {
                revert HostNotReady();
            }
            hosts[hostIds[i]].state = HostState.InSpiral;
        }

        uint256 requestId = requestRandomness(3);
        requests[requestId] = ChainLinkRequest({
            scenaryId: 0,
            spiralId: spiralId,
            randomness: new uint8[](ATTR_COUNT)
        });

        spirals[spiralId].state = SpiralState.InProgress;
        emit SpiralStarted(spiralId, requestId);
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

    function getHost(
        bytes32 hostId
    ) external view returns (uint8[10] memory, uint8) {
        Host memory host = hosts[hostId];
        return (host.attributes, host.health);
    }

    function getRequest(
        uint256 requestId
    ) external view returns (uint8[] memory, uint8) {
        ChainLinkRequest memory request = requests[requestId];
        return (request.randomness, request.spiralId);
    }

    /**
     * INTERNAL METHODS
     */

    /// @notice Execute the run when it is full.
    function playRound(uint8 spiralId, uint256 requestId) internal {
        Spiral storage spiral = spirals[spiralId];

        bytes32[] storage currentHostIds = hostIdsBySpiral[spiralId];
        uint8[] memory randomness = requests[requestId].randomness;

        uint8 scenaryId = requests[requestId].scenaryId;
        for (uint i = currentHostIds.length; i > 0; i--) {
            bytes32 hostId = currentHostIds[i - 1];
            processHost(spiralId, hostId, scenaryId, randomness);

            if (currentHostIds.length == 1) {
                bytes32 winner = currentHostIds[0];
                delete hostIdsBySpiral[spiralId];
                spiral.state = SpiralState.Completed;
                spiral.winner = hosts[winner].pass;
                hosts[hostId].state = HostState.NotReady;
                emit SpiralFinished(spiralId, winner);
                return;
            }
        }

        uint16 seconds_per_block_approximately = (spiral.countdownDelay *
            spiral.round) / 15;
        uint256 nextRequestId = requestRandomness(
            seconds_per_block_approximately
        );
        requests[nextRequestId] = ChainLinkRequest({
            scenaryId: 0,
            spiralId: spiralId,
            randomness: new uint8[](ATTR_COUNT)
        });

        spiral.round += 1;
        emit RoundPlayed(spiralId, scenaryId, spiral.round, nextRequestId);
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
        playRound(requests[requestId].spiralId, requestId);
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

    function removeHostIdFromSpiral(
        uint8 spiralId,
        bytes32 hostId
    ) internal {
        bytes32[] storage hostIds = hostIdsBySpiral[spiralId];
        uint256 indexToRemove = hostIds.length;
        for (uint256 i = 0; i < hostIds.length; i++) {
            if (hostIds[i] == hostId) {
                indexToRemove = i;
                break;
            }
        }

        if (indexToRemove < hostIds.length) {
            hostIds[indexToRemove] = hostIds[hostIds.length - 1];
            hostIds.pop();
        }
        emit HostEliminated(spiralId, hostId);
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

    function processHost(
        uint8 spiralId,
        bytes32 hostId,
        uint8 scenaryId,
        uint8[] memory randomness
    ) internal {
        Host storage host = hosts[hostId];
        for (uint j = 0; j < ATTR_COUNT; j++) {
            uint8 adjustedHostAttr = adjustAttribute(
                host.attributes[j],
                incrementModifiers[scenaryId][j],
                decrementModifiers[scenaryId][j]
            );
            if (randomness[j] > adjustedHostAttr) {
                if (host.health > 1) {
                    host.health--;
                } else {
                    removeHostIdFromSpiral(spiralId, hostId);
                    host.state = HostState.NotReady;
                    break;
                }
            }
        }
    }
}
