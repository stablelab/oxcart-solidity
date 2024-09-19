// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/Oxcart.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract OxcartTest is Test {
    Oxcart private oxcartImplementation;
    TransparentUpgradeableProxy private proxy;
    Oxcart private oxcart;
    MockERC20 private mockToken;

    address private owner = address(1);
    address private delegate1 = address(2);
    address private delegate2 = address(3);
    address private backupVoter = address(4);

    event TestLog(string message);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy the implementation contract
        oxcartImplementation = new Oxcart();

        // Deploy the TransparentUpgradeableProxy contract
        proxy = new TransparentUpgradeableProxy(
            address(oxcartImplementation),
            owner, // Proxy admin is set to owner
            abi.encodeWithSelector(Oxcart.initialize.selector, owner)
        );

        // Point oxcart to the proxy address
        oxcart = Oxcart(address(proxy));

        // Set up the mock token
        mockToken = new MockERC20();
        oxcart.setLotteryPaymentTokenContractAndDecimals(address(mockToken), 18);
        mockToken.mint(address(proxy), 1000 ether);
        emit log_uint(mockToken.balanceOf(owner));

        // Register top delegates
        address[] memory delegates = new address[](2);
        delegates[0] = delegate1;
        delegates[1] = delegate2;
        registerTopDelegates(delegates);

        vm.stopPrank();
    }

    function registerTopDelegates(address[] memory delegates) internal {
        vm.startPrank(owner);
        oxcart.registerTopDelegates(delegates);
        vm.stopPrank();
        emit TestLog("Top delegates registered");
    }

    function testRegisterTopDelegates() public {
        address[] memory topDelegates = oxcart.getTopDelegates();
        assertEq(topDelegates.length, 2);
        assertEq(topDelegates[0], delegate1);
        assertEq(topDelegates[1], delegate2);
        emit TestLog("Top delegates registration test passed");
    }

    function testSetBackupVoter() public {
        vm.prank(delegate1);
        oxcart.setBackupVoter(delegate2);

        address setBackupVoter = oxcart.getBackupVoter(delegate1);
        assertEq(setBackupVoter, delegate2);
        emit TestLog("Backup voter set successfully");
    }

    function testRemoveTopDelegate() public {
        vm.prank(owner);
        oxcart.removeTopDelegate(delegate1);

        address[] memory topDelegates = oxcart.getTopDelegates();
        assertEq(topDelegates.length, 1);
        assertEq(topDelegates[0], delegate2);

        assertFalse(oxcart.isTopDelegateCheck(delegate1));
        emit TestLog("Top delegate removed successfully");
    }

    function test_set_tickets_manually() public {
        // Setup: Register two top delegates and set one as the backup of the other
        vm.startPrank(owner);
        address[] memory delegates = new address[](2);
        delegates[0] = delegate1;
        delegates[1] = delegate2;
        oxcart.registerTopDelegates(delegates);
        vm.stopPrank();

        vm.prank(delegate1);
        oxcart.setBackupVoter(delegate2);

        vm.prank(delegate2);
        oxcart.setBackupVoter(delegate1);

        // Check initial state
        assertEq(oxcart.getBackupVoter(delegate1), delegate2, "Backup voter1 not set correctly");
        assertEq(oxcart.getBackupVoter(delegate2), delegate1, "Backup voter2 not set correctly");

        // Set tickets manually
        vm.prank(owner);
        uint[] memory _tickets = new uint256[](2);
        _tickets[0] = 10 ether;
        _tickets[1] = 20 ether;
        oxcart.manual_override_setLotteryTickets(delegates, _tickets);

        // Verify results
        uint[] memory tickets = oxcart.getLotteryTickets();
        for (uint i = 0; i < tickets.length; i++) {
            emit log_named_uint("Array Element", tickets[i]);
        }
        assertTrue(tickets.length > 0, "No tickets calculated");
        if (tickets.length > 0) {
            assertEq(10 ether, tickets[0], "Ticket calculation failed or mismatched");
            assertEq(20 ether, tickets[1], "Ticket calculation failed or mismatched");
        }
    }

    function test_lottery_payout() public {
        vm.startPrank(owner);
        address[] memory delegates = new address[](2);
        delegates[0] = delegate1;
        delegates[1] = delegate2;
        oxcart.registerTopDelegates(delegates);
        vm.stopPrank();

        vm.prank(delegate1);
        oxcart.setBackupVoter(delegate2);

        vm.prank(delegate2);
        oxcart.setBackupVoter(delegate1);

        // Set tickets manually
        vm.prank(owner);
        uint[] memory _tickets = new uint256[](2);
        _tickets[0] = 1000 ether;
        oxcart.manual_override_setLotteryTickets(delegates, _tickets);

        // Register lottery draw event
        vm.prank(owner);
        oxcart.registerLotteryDrawEvent(1);

        // Set lottery payout amount
        vm.prank(owner);
        oxcart.setLotteryPayoutAmount(1);

        emit log_uint(mockToken.balanceOf(address(this)));

        // Execute lottery payout
        vm.prank(owner);
        oxcart.drawAndPayoutLottery(0);

        // Verify results
        uint balance = mockToken.balanceOf(delegate1);
        assertEq(balance, 1, "Lottery payout failed or mismatched");
        // Get lottery winners and payouts
        vm.prank(owner);
        Oxcart.LotteryEvent[] memory lotteryEvents = oxcart.getLotteryWinnersAndPayouts();

        // Verify results
        for (uint i = 0; i < lotteryEvents.length; i++) {
            emit log_named_uint("Block Height", lotteryEvents[i].blockHeight);
            emit log_named_address("Winner", lotteryEvents[i].winner);
            emit log_named_uint("Payout", lotteryEvents[i].payout);
        }
    }

    function testRandomNumber() public {
        uint randomNumber = oxcart.getRandomNumber();
        emit log_uint(randomNumber);
    }

     function test_emergency_withdraw() public {
        vm.startPrank(owner);
        mockToken.mint(address(oxcart), 1000 ether);
        uint prev_balancer = mockToken.balanceOf(address(oxcart));
        uint prev_balancer_owner = mockToken.balanceOf(address(owner));
        oxcart.emergency_withdraw(address(mockToken), owner, mockToken.balanceOf(address(oxcart)));
        assertEq(mockToken.balanceOf(address(oxcart)), 0 ether);
        assertEq(mockToken.balanceOf(address(owner)), prev_balancer_owner + prev_balancer);
        emit log_uint(mockToken.balanceOf(address(oxcart)));
     }
}
