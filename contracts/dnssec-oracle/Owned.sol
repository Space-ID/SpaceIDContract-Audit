pragma solidity ^0.8.4;

/**
* @dev Contract mixin for 'owned' contracts.
*/
contract Owned {
    address public owner;

    event OwnerSet(address newOwner);
    
    modifier owner_only() {
        require(msg.sender == owner);
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function setOwner(address newOwner) public owner_only {
        require(newOwner != address(0), "address can not be zero!");
        emit OwnerSet(newOwner);
        owner = newOwner;
    }
}
