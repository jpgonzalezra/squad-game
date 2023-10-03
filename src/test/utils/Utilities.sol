// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";

// common utilities for forge tests
contract Utilities is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

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
        uint256 numWords
    ) public pure returns (uint256[] memory) {
        uint256[] memory words = new uint256[](numWords);
        for (uint256 i = 0; i < numWords; i++) {
            words[i] = uint256(keccak256(abi.encode(requestId, i)));
        }
        return words;
    }
}
