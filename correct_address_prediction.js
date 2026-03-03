const { ethers } = require('ethers');

// Test parameters from the user's request
const BEACON_ADDRESS = '0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C';
const OWNER = '0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6';
const SALT = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
const EXPECTED_RESULT = '0x6DFeD3087CbfAA7E8C920AcCEcb20C985C7961Fc';
const FOUNDATION_ADDRESS = '0x3Ec0108A3e6A530D8eF1c123F16a55D803c29948';

// Function to replicate LibClone's initCodeHashERC1967BeaconProxy with args
function initCodeHashERC1967BeaconProxy(beacon, args) {
    const argsLength = args.length;
    
    // Check if args length is too large (greater than 0xffad)
    if (argsLength > 0xffad) {
        throw new Error('Args too large');
    }
    
    // Create the init code structure based on the assembly layout
    // Memory layout from assembly:
    // m: free memory pointer
    // mstore(m, add(0x6100523d8160233d3973, shl(56, n))) - prefix with length
    // mstore(add(m, 0x14), beacon) - beacon at offset 0x14
    // mstore(add(add(m, 0x8b), i), mload(add(add(args, 0x20), i))) - args at offset 0x8b
    // mstore(add(m, 0x2b), 0x60195155f3363d3d373d3d363d602036600436635c60da) - runtime code 1
    // mstore(add(m, 0x4b), 0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c) - runtime code 2
    // mstore(add(m, 0x6b), 0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3) - runtime code 3
    // hash := keccak256(add(m, 0x16), add(n, 0x75))
    
    const totalLength = 0x16 + argsLength + 0x75;
    const initCode = new Uint8Array(totalLength);
    
    // 1. Store the prefix with args length at offset 0: 0x6100523d8160233d3973 + (argsLength << 56)
    const prefix = 0x6100523d8160233d3973n + (BigInt(argsLength) << 56n);
    const prefixBytes = new Uint8Array(8);
    for (let i = 0; i < 8; i++) {
        prefixBytes[7 - i] = Number((prefix >> (BigInt(i) * 8n)) & 0xFFn);
    }
    initCode.set(prefixBytes, 0);
    
    // 2. Store the beacon address at offset 0x14 (20 bytes)
    const beaconBytes = ethers.getBytes(beacon);
    initCode.set(beaconBytes, 0x14);
    
    // 3. Store the args data at offset 0x8b
    const argsBytes = ethers.getBytes(args);
    initCode.set(argsBytes, 0x8b);
    
    // 4. Store the runtime code parts
    const runtimeCode1 = '0x60195155f3363d3d373d3d363d602036600436635c60da';
    const runtimeCode2 = '0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c';
    const runtimeCode3 = '0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3';
    
    initCode.set(ethers.getBytes(runtimeCode1), 0x2b);
    initCode.set(ethers.getBytes(runtimeCode2), 0x4b);
    initCode.set(ethers.getBytes(runtimeCode3), 0x6b);
    
    // Calculate hash starting from offset 0x16 (22 bytes from start)
    const hashStart = 0x16;
    const hashLength = argsLength + 0x75;
    const hashData = initCode.slice(hashStart, hashStart + hashLength);
    
    return ethers.keccak256(hashData);
}

// Function to replicate LibClone's predictDeterministicAddress
function predictDeterministicAddress(hash, salt, deployer) {
    // Create the data for keccak256: 0xff + deployer + salt + hash
    const data = ethers.concat([
        '0xff',
        deployer,
        salt,
        hash
    ]);
    
    const hashResult = ethers.keccak256(data);
    // Extract the last 20 bytes (40 hex characters) for the address
    return '0x' + hashResult.slice(-40);
}

// Main calculation function
function computeCharterAddress(beacon, owner, salt, foundation) {
    // Create the args exactly like Solidity abi.encodeWithSelector
    // This should be: selector (4 bytes) + address1 (32 bytes) + address2 (32 bytes) = 68 bytes
    const address1Encoded = ethers.AbiCoder.defaultAbiCoder().encode(['address'], [foundation]);
    const address2Encoded = ethers.AbiCoder.defaultAbiCoder().encode(['address'], [owner]);
    
    // Create the args as raw bytes
    const selectorBytes = ethers.getBytes('0x485cc955');
    const address1Bytes = ethers.getBytes(address1Encoded);
    const address2Bytes = ethers.getBytes(address2Encoded);
    
    const args = new Uint8Array(4 + 32 + 32);
    args.set(selectorBytes, 0);
    args.set(address1Bytes, 4);
    args.set(address2Bytes, 36);
    
    console.log('Args:', ethers.hexlify(args));
    console.log('Args length:', args.length);
    
    // Get the init code hash
    const initCodeHash = initCodeHashERC1967BeaconProxy(beacon, args);
    console.log('Init code hash:', initCodeHash);
    
    // Calculate the predicted address
    const predicted = predictDeterministicAddress(initCodeHash, salt, foundation);
    console.log('Predicted address:', predicted);
    
    return predicted;
}

// Test the calculation
console.log('=== ERC1967 Beacon Proxy Address Prediction Test ===');
console.log('Beacon Address:', BEACON_ADDRESS);
console.log('Owner:', OWNER);
console.log('Salt:', SALT);
console.log('Foundation (Deployer):', FOUNDATION_ADDRESS);
console.log('Expected Result:', EXPECTED_RESULT);
console.log('');

const result = computeCharterAddress(BEACON_ADDRESS, OWNER, SALT, FOUNDATION_ADDRESS);

console.log('');
console.log('=== Results ===');
console.log('Calculated:', result);
console.log('Expected:  ', EXPECTED_RESULT);
console.log('Match:', result.toLowerCase() === EXPECTED_RESULT.toLowerCase() ? '✅ SUCCESS' : '❌ FAILED');

// Additional test with different parameters
console.log('');
console.log('=== Additional Test Cases ===');

// Test case 2
const test2Beacon = '0x1234567890123456789012345678901234567890';
const test2Owner = '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd';
const test2Salt = '0x0000000000000000000000000000000000000000000000000000000000000001';
const test2Foundation = '0x1111111111111111111111111111111111111111';

console.log('Test 2:');
console.log('Beacon:', test2Beacon);
console.log('Owner:', test2Owner);
console.log('Salt:', test2Salt);
console.log('Foundation:', test2Foundation);
const result2 = computeCharterAddress(test2Beacon, test2Owner, test2Salt, test2Foundation);
console.log('Result:', result2);
