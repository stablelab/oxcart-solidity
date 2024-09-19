// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Oxcart is Initializable, OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private topDelegates;
    EnumerableSet.AddressSet private backupVoterList;
    mapping(address => address) public backupVoters;
    mapping(address => uint256) public backupVotersSinceBlockTimestamp;
    mapping(address => bool) public isTopDelegate;

    // Lottery Related
    mapping(uint => uint) public lotteryEvents;
    mapping(uint => bool) public lotteryDrawn;
    mapping(uint => address) public lotteryWinners;
    mapping(uint => uint) public lotteryPayouts;
    mapping(address => uint) public tickets;
    uint lotteryEventsCount = 0;

    // Ticket Power Related
    uint public BASE_TICKETS = 1 ether;

    uint lotteryPayoutAmount;
    IERC20 public lotteryPaymentTokenContract;
    uint256 public lotteryPaymentTokenContractDecimals;

    struct BackupVoter {
        address delegate;
        address backupVoter;
    }

    struct LotteryEvent {
        uint blockHeight;
        bool drawn;
        address winner;
        uint payout;
    }

    event DelegateRegistered(address indexed delegate);
    event BackupVoterSet(address indexed delegate, address indexed backupVoter);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    function setLotteryPaymentTokenContractAndDecimals(address _lotteryPaymentTokenContract, uint _lotteryPaymentTokenContractDecimals) external onlyOwner {
        lotteryPaymentTokenContract = IERC20(_lotteryPaymentTokenContract);
        lotteryPaymentTokenContractDecimals = _lotteryPaymentTokenContractDecimals;
    }

    modifier onlyTopDelegate() {
        require(isTopDelegate[_msgSender()], "Not a top delegate");
        _;
    }

    function registerTopDelegates(address[] memory delegates) external onlyOwner {
        for (uint256 i = 0; i < delegates.length; i++) {
            if (topDelegates.add(delegates[i])) {
                isTopDelegate[delegates[i]] = true;
                emit DelegateRegistered(delegates[i]);
            }
        }
    }

    function removeTopDelegate(address delegate) external onlyOwner {
        if (topDelegates.remove(delegate)) {
            isTopDelegate[delegate] = false;
            if (backupVoterList.contains(delegate)) {
                backupVoterList.remove(delegate);
                delete backupVoters[delegate];
            }
        }
    }

    function setBackupVoter(address backupVoter) external {
        require(isTopDelegate[backupVoter], "Backup voter must be a top delegate");
        require(backupVoter != _msgSender(), "Cannot set self as backup");
        backupVoters[_msgSender()] = backupVoter;
        backupVotersSinceBlockTimestamp[_msgSender()] = block.timestamp;
        backupVoterList.add(_msgSender()); // Ensure the key is added to the set
        emit BackupVoterSet(_msgSender(), backupVoter);
    }

    function setLotteryPayoutAmount(uint _lotteryPayoutAmount) external onlyOwner {
        lotteryPayoutAmount = _lotteryPayoutAmount;
    }

    function getBackupVoter(address delegate) external view returns (address) {
        return backupVoters[delegate];
    }

    function getTopDelegates() external view returns (address[] memory) {
        return topDelegates.values();
    }

    function isTopDelegateCheck(address delegate) external view returns (bool) {
        return isTopDelegate[delegate];
    }

    function getBackupVoters() external view returns (BackupVoter[] memory) {
        BackupVoter[] memory backupVotersList = new BackupVoter[](backupVoterList.length());
        for (uint256 i = 0; i < backupVoterList.length(); i++) {
            address delegate = backupVoterList.at(i);
            backupVotersList[i] = BackupVoter({
                delegate: delegate,
                backupVoter: backupVoters[delegate]
            });
        }
        return backupVotersList;
    }

    function registerLotteryDrawEvent(uint blockHeight) external onlyOwner {
        lotteryEvents[lotteryEventsCount] = blockHeight;
        lotteryEventsCount++;
    }

    function manual_override_setLotteryTickets(address[] memory delegates, uint256[] memory _tickets) external onlyOwner {
        require(delegates.length == _tickets.length, "Delegates and tickets length mismatch");
        address[] memory participants = backupVoterList.values();
        for (uint i = 0; i < participants.length; i++) {
            tickets[participants[i]] = 0;
        }
        for (uint i = 0; i < delegates.length; i++) {
            tickets[delegates[i]] = _tickets[i];
        }
    }

    function getTotalTickets() internal view returns (uint) {
        uint totalTickets = 0;
        for (uint i = 0; i < backupVoterList.length(); i++) {
            address delegate = backupVoterList.at(i);
            totalTickets += tickets[delegate];
        }
        return totalTickets;
    }

    function getRandomNumber() public view returns (uint) {
        return uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, getTotalTickets())));
    }

    function drawAndPayoutLottery(uint lotteryId) external onlyOwner returns (address) {
        require(getTotalTickets() > 0, "No tickets set for lottery");
        require(!lotteryDrawn[lotteryId], "Lottery already drawn");
        require(block.number >= lotteryEvents[lotteryId], "Lottery draw event for this lottery is unavaialble");
        lotteryDrawn[lotteryId] = true;
        uint256 totalTickets = getTotalTickets();

        // For Testing purposes only; Replace with Chainlink VRF in prod
        uint randomNumber = getRandomNumber() % totalTickets;
        
        uint256 cumulativeSum = 0;
        address winner = address(0);
        for (uint256 i = 0; i < backupVoterList.length(); i++) {
            address delegate = backupVoterList.at(i);
            cumulativeSum += tickets[delegate];
            if (randomNumber < cumulativeSum) {
                winner = delegate;
                break;
            }
        }

        require(address(lotteryPaymentTokenContract) != address(0), "Lottery payment token contract not set");
        // require(lotteryPaymentTokenContract.balanceOf(address(this)) >= lotteryPayoutAmount, "Insufficient balance for payout");
        // lotteryPaymentTokenContract.transfer(winner, lotteryPayoutAmount);
        lotteryWinners[lotteryId] = winner;
        lotteryPayouts[lotteryId] = lotteryPayoutAmount;
        return winner;
    }

    function emergency_withdraw(address token, address to, uint amount) external onlyOwner {
        ERC20(token).transfer(to, amount);
    }

    function emergency_withdraw_eth(address to, uint amount) external onlyOwner {
        payable(to).transfer(amount);
    }

    function getLotteryTickets() external view returns (uint[] memory) {
        uint[] memory ticketsList = new uint[](backupVoterList.length());
        for (uint256 i = 0; i < backupVoterList.length(); i++) {
            address delegate = backupVoterList.at(i);
            ticketsList[i] = tickets[delegate];
        }
        return ticketsList;
    }

    function getLotteryWinnersAndPayouts() external view returns (LotteryEvent[] memory) {
        LotteryEvent[] memory resultsLotteryEvents = new LotteryEvent[](lotteryEventsCount);
        for (uint i = 0; i < lotteryEventsCount; i++) {
            resultsLotteryEvents[i] = LotteryEvent({
                blockHeight: lotteryEvents[i],
                drawn: lotteryDrawn[i],
                winner: lotteryWinners[i],
                payout: lotteryPayouts[i]
            });
        }
        return resultsLotteryEvents;
    }
}
