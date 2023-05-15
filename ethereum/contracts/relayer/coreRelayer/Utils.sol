// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

error NotAnEvmAddress(bytes32);

function pay(address payable receiver, uint256 amount) returns (bool success) {
  if (amount != 0)
    (success,) = receiver.call{value: amount}("");
  else
    success = true;
}

function min(uint256 a, uint256 b) pure returns (uint256) {
  return a < b ? a : b;
}

function max(uint256 a, uint256 b) pure returns (uint256) {
  return a > b ? a : b;
}

function toWormholeFormat(address addr) pure returns (bytes32) {
  return bytes32(uint256(uint160(addr)));
}

function fromWormholeFormat(bytes32 whFormatAddress) pure returns (address) {
  if (uint256(whFormatAddress) >> 160 != 0)
    revert NotAnEvmAddress(whFormatAddress);
  return address(uint160(uint256(whFormatAddress)));
}

function fromWormholeFormatUnchecked(bytes32 whFormatAddress) pure returns (address) {
  return address(uint160(uint256(whFormatAddress)));
}


uint256 constant freeMemoryPtr = 0x40;
uint256 constant memoryWord = 32;
uint256 constant maskModulo32 = 0x1f;
// Bound chosen by the following formula: `memoryWord * 4 + selectorSize`.
// This means that an error identifier plus four fixed size arguments should be available to developers.
// In the case of a `require` revert with error message, this should provide 3 memory word's worth of data.
uint256 constant returnLengthBound = 132;

/**
 * Implements call that truncates return data to a constant size to avoid excessive gas consumption for relayers
 * when a revert or .
 */
function returnLengthBoundedCall(address payable callee, bytes memory callData, uint256 gasLimit, uint256 value) returns (bool success, bytes memory returnedData) {
  uint256 callDataLength = callData.length;
  assembly ("memory-safe") {
    returnedData := mload(freeMemoryPtr)
    // Note that `returnedDataEndIndex` and `callDataEndIndex` are past the end indexes for their respective buffers.
    let returnedDataBuffer := add(returnedData, memoryWord)
    let returnedDataEndIndex := add(returnedDataBuffer, returnLengthBound)
    let callDataEndIndex := add(callData, callDataLength)

    success := call(gasLimit, callee, value, callData, callDataEndIndex, returnedDataBuffer, returnedDataEndIndex)
    let returnedDataSize := returndatasize()
    switch lt(returnedDataSize, add(returnLengthBound, 1))
    case 0 {
      returnedDataSize := returnLengthBound
    } default {}
    mstore(returnedData, returnedDataSize)

    // Here we update the free memory pointer.
    // We want to pad `returnedData` to memory word size, i.e. 32 bytes.
    // Note that negating bitwise `maskModulo32` produces a mask that aligns addressing to 32 bytes.
    // This allows us to pad the entire `bytes` structure (length + buffer) to 32 bytes at the end.
    // We add `maskModulo32` to get the next free memory "slot" in case the `returnedDataSize` is not a multiple of the memory word size.
    //
    // Rationale:
    // We do not care about the alignment of the free memory pointer. The solidity compiler documentation does not promise nor require alignment on it.
    // It does however lightly suggest to pad `bytes` structures to 32 bytes: https://docs.soliditylang.org/en/v0.8.20/assembly.html#example
    // Searching for "alignment" and "padding" in https://gitter.im/ethereum/solidity-dev
    // yielded the following at the time of writing – paraphrased:
    // > It's possible that the compiler cleans that padding in some cases. Users should not rely on the compiler never doing that.
    // This means that we want to ensure that the free memory pointer points to memory just after this padding for our `returnedData` `bytes` structure.
    let paddedPastTheEndOffset := and(add(returnedDataSize, maskModulo32), not(maskModulo32))
    let newFreeMemoryPtr := add(returnedDataBuffer, paddedPastTheEndOffset)
    mstore(freeMemoryPtr, newFreeMemoryPtr)
  }
}
