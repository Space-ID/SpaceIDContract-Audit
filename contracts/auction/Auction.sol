pragma solidity >=0.8.4;

contract Auction {
    // static
    address public owner;
    uint public bidIncrement;
    uint public startBlock;
    uint public endBlock;
    string public name;
    mapping (address => bool) public allowedBidder;

    // state
    address public highestBidder;
    mapping(address => uint256) public fundsByBidder;
    bool public ownerHasWithdrawn;

    event LogBid(address bidder, uint bid, address highestBidder, uint highestBid);
    event LogWithdrawal(address withdrawer, address withdrawalAccount, uint amount);

    constructor(address _owner,
                uint _startPrice,
                uint _startBlock,
                uint _endBlock,
                string memory _name,
                address[] memory _addresses) {
        require(_startBlock + 1 < _endBlock);
        require(_startBlock > block.number);
        require(_owner != address(0));

        owner = _owner;
        // at the very beginning it's the base price, every bid will increase 5%
        bidIncrement = 0;
        fundsByBidder[highestBidder] = _startPrice;
        startBlock = _startBlock;
        endBlock = _endBlock;
        name = _name;
        for (uint256 i=0; i<_addresses.length; i++) {
            allowedBidder[_addresses[i]] = true;
        }
    }

    function getHighestBid()
        public
        view
        returns (uint)
    {
        return fundsByBidder[highestBidder];
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function placeBid()
        payable
        onlyAfterStart
        onlyBeforeEnd
        onlyNotOwner
        onlyAllowedBidder
        public returns (bool success)
    {
        // reject payments of 0 ETH
        require (msg.value > 0, "can't bid with 0 value") ;
        uint newBid = fundsByBidder[msg.sender] + msg.value;
        uint highestBid = fundsByBidder[highestBidder];
        require (newBid >= (highestBid + bidIncrement), "must be equal to or larger than current best bid");
        fundsByBidder[msg.sender] = newBid;
        highestBid = newBid;
        highestBidder = msg.sender;
        bidIncrement = max((highestBid * 105 / 100) - highestBid, bidIncrement);

        emit LogBid(msg.sender, newBid, highestBidder, highestBid);
        return true;
    }

    function min(uint a, uint b)
        private
        pure 
        returns (uint)
    {
        if (a < b) return a;
        return b;
    }

    function withdraw()
        onlyEnded
        public returns (bool success)
    {
        address withdrawalAccount;
        uint withdrawalAmount;

	// the auction finished without being
	require(msg.sender != highestBidder, "winner can not withdraw!");
	if (msg.sender == owner) {
	    // the auction's owner should be allowed to withdraw the highestBindingBid
	    withdrawalAccount = highestBidder;
	    withdrawalAmount = fundsByBidder[highestBidder];
	    ownerHasWithdrawn = true;
	} else {
	    // anyone who participated but did not win the auction should be allowed to withdraw
	    // the full amount of their funds
	    withdrawalAccount = msg.sender;
	    withdrawalAmount = fundsByBidder[withdrawalAccount];
	}

	require (withdrawalAmount > 0, "amount must be larger than 0");

        fundsByBidder[withdrawalAccount] -= withdrawalAmount;

        // send the funds
	    payable(msg.sender).transfer(withdrawalAmount);

        emit LogWithdrawal(msg.sender, withdrawalAccount, withdrawalAmount);

        return true;
    }

    modifier onlyOwner {
        require (msg.sender == owner, "must be owner!");
        _;
    }

    modifier onlyNotOwner {
        require (msg.sender != owner, "must not be owner!");
        _;
    }

    modifier onlyAfterStart {
        require (block.number > startBlock, "only after start!") ;
        _;
    }

    modifier onlyBeforeEnd {
        require (block.number < endBlock, "already end!") ;
        _;
    }

    modifier onlyEnded {
        require(block.number > endBlock, "must be ended!") ;
        _;
    }

    modifier onlyAllowedBidder {
        require (allowedBidder[msg.sender], "you are not allowed to bid!");
        _;
    }
}
