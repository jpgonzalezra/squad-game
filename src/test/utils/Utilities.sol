// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../SquadGame.sol";
import "forge-std/console.sol";

// common utilities for forge tests
contract Utilities is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    struct SquadInfo {
        address lider;
        bytes32 squadId;
        uint8[10] attributes;
    }

    function getNextUserAddress() external returns (address payable) {
        // bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    // fund user with 100 ether
    function fundSpecificAddress(address userAddress) external {
        vm.deal(userAddress, 100 ether);
    }

    // move block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks) external {
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
    }

    function getWords(
        uint256 requestId,
        uint256 numWords,
        uint256 range
    ) public view returns (uint256[] memory) {
        uint256[] memory words = new uint256[](numWords);
        for (uint256 i = 0; i < numWords; i++) {
            console.log(
                "Words",
                (uint256(keccak256(abi.encode(requestId, i))) % (range + 1))
            );
            words[i] = (uint256(keccak256(abi.encode(requestId, i))) %
                (range + 1));
        }
        return words;
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
    ) public pure returns (bytes32 squadId, uint8[10] memory attributes) {
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

    function createAndSetupSquadInfo(
        uint8[10] memory attributes,
        address leader
    ) public pure returns (SquadInfo memory) {
        (bytes32 squadId, uint8[10] memory squadAttributes) = createSquad(
            attributes[0],
            attributes[1],
            attributes[2],
            attributes[3],
            attributes[4],
            attributes[5],
            attributes[6],
            attributes[7],
            attributes[8],
            attributes[9]
        );
        return
            SquadInfo({
                lider: leader,
                squadId: squadId,
                attributes: squadAttributes
            });
    }
}
