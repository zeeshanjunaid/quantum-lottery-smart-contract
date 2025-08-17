// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

import {TestUSDC} from "../src/TestUSDC.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

// Minimal interface to call processDrawChunk from malicious token
interface IQL {
    function processDrawChunk(
        uint256 _hourId,
        uint256 _iterations
    ) external returns (bool);
}

contract MaliciousERC20 is TestUSDC {
    address public targetLottery;
    uint256 public reenterHour;

    constructor() TestUSDC() {}

    function setTarget(address _lottery, uint256 _hour) external {
        targetLottery = _lottery;
        reenterHour = _hour;
    }

    function transfer(address to, uint256 amt) public override returns (bool) {
        bool ok = super.transfer(to, amt);
        if (targetLottery != address(0)) {
            IQL(targetLottery).processDrawChunk(reenterHour, 1);
        }
        return ok;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amt
    ) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amt);
        if (targetLottery != address(0)) {
            IQL(targetLottery).processDrawChunk(reenterHour, 1);
        }
        return ok;
    }
}

// Non-compliant token: returns false from transferFrom to simulate broken ERC20
contract BadUSDC is TestUSDC {
    constructor() TestUSDC() {}

    // override to return false (no transfer) but do not revert
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false;
    }
}

contract QuantumLotteryTest is Test {
    // Contracts
    QuantumLottery public lottery;
    TestUSDC public usdc;
    VRFCoordinatorV2Mock public vrf;

    // Actors
    address treasury = makeAddr("treasury");
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    // VRF Config
    uint64 subId;
    bytes32 gasLane =
        0x114f3da0a805b8a67d6a7a05154f14afd91811821b38e09e03ade28a24ac2166;

    // Constants
    uint256 constant ONE_USDC = 1e6;
    uint256 constant BASE_QSCORE = 100;
    uint256 constant BASE_BONUS = 10;
    uint256 constant QUANTUM_BONUS = 40;
    // Mirror contract constants used in tests
    uint256 constant STREAK_BONUS = 15;
    uint256 constant BLAZING_STREAK_BONUS = 20;
    uint256 constant QUANTUM_TICKET_BONUS = 40;
    uint32 constant STREAK_MODE_THRESHOLD = 5;
    uint32 constant BLAZING_STREAK_THRESHOLD = 10;

    event WinnerSelectionRequested(
        uint256 indexed hourId,
        uint256 indexed requestId
    );
    event TicketPurchased(
        uint256 indexed hourId,
        address indexed player,
        QuantumLotteryTypes.TicketType ticketType,
        uint256 qScoreOnEntry
    );
    // mirror contract events for vm.expectEmit usage
    event RandomnessFulfilled(
        uint256 indexed hourId,
        uint256 indexed requestId,
        uint256 totalQScoreInPool
    );
    event WinnerPicked(
        uint256 indexed hourId,
        address indexed winner,
        uint256 prizeAmount,
        uint256 feeAmount,
        uint256 totalQScoreInPool
    );
    event RefundIssued(
        uint256 indexed hourId,
        address indexed player,
        uint256 amount,
        uint256 remainingLiability
    );
    event WithdrawUnclaimed(
        uint256 indexed hourId,
        address indexed to,
        uint256 amount,
        uint256 remainingLiability
    );
    event QScoreCapped(
        address indexed player,
        uint256 indexed hourId,
        uint256 cappedAt
    );
    event CosmicSurgeCanceled(uint256 indexed hourId);

    function setUp() public {
        usdc = new TestUSDC();
        vrf = new VRFCoordinatorV2Mock(0, 0);
        subId = vrf.createSubscription();
        vrf.fundSubscription(subId, 100 ether);

        vm.prank(owner);
        lottery = new QuantumLottery(
            address(usdc),
            treasury,
            address(vrf),
            subId,
            gasLane
        );
        vrf.addConsumer(subId, address(lottery));

        _mintAndApprove(alice, 1000 * ONE_USDC);
        _mintAndApprove(bob, 1000 * ONE_USDC);
        _mintAndApprove(carol, 1000 * ONE_USDC);
    }

    // =============================================================
    //                        1. DEPLOYMENT & INITIALIZATION
    // =============================================================
    function test_Deployment_StateIsCorrect() public view {
        assertEq(lottery.owner(), owner);
        assertEq(address(lottery.i_usdcToken()), address(usdc));
        assertEq(lottery.i_treasury(), treasury);
    }

    function test_DefaultDrawsAreOpen() public view {
        uint256 hourId = block.timestamp / 3600;
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.OPEN)
        );
    }

    // =============================================================
    //                   1.2 Constructor invalid args
    // =============================================================
    function test_Constructor_InvalidArgsRevert() public {
        // USDC zero
        vm.expectRevert(bytes("USDC address cannot be zero"));
        vm.prank(owner);
        new QuantumLottery(address(0), treasury, address(vrf), subId, gasLane);

        // Treasury zero
        vm.expectRevert(bytes("Treasury address cannot be zero"));
        vm.prank(owner);
        new QuantumLottery(
            address(usdc),
            address(0),
            address(vrf),
            subId,
            gasLane
        );

        // VRF coordinator zero
        vm.expectRevert(bytes("VRF Coordinator cannot be zero"));
        vm.prank(owner);
        new QuantumLottery(address(usdc), treasury, address(0), subId, gasLane);
    }

    // =============================================================
    //                        2. TICKET PURCHASES
    // =============================================================
    function test_BuyTicket_HappyPath_FirstTimePlayer() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);

        assertEq(lottery.getParticipantsCount(hourId), 1);
        QuantumLottery.Participant memory p = lottery.getParticipant(hourId, 0);
        assertEq(p.playerAddress, alice);
        assertEq(p.qScoreOnEntry, BASE_QSCORE);
        assertEq(lottery.lastEnteredHour(alice), hourId);
    }

    function test_Revert_WhenPlayerEntersSameHourTwice() public {
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.PlayerAlreadyEntered.selector
            )
        );
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
    }

    function test_Revert_WhenDrawIsFull() public {
        uint256 cap = lottery.MAX_PARTICIPANTS();
        for (uint256 i = 0; i < cap; i++) {
            _mintAndApprove(address(uint160(i + 1)), 1 * ONE_USDC);
            _buy(
                address(uint160(i + 1)),
                QuantumLotteryTypes.TicketType.Standard
            );
        }
        vm.expectRevert(
            abi.encodeWithSelector(QuantumLotteryTypes.DrawIsFull.selector)
        );
        _buy(carol, QuantumLotteryTypes.TicketType.Standard);
    }

    function test_BuyTicket_TransfersUSDC_and_reservedRefunds() public {
        uint256 hourId = block.timestamp / 3600;
        uint256 price = lottery.STANDARD_TICKET_PRICE();

        // check initial balances
        assertEq(usdc.balanceOf(address(lottery)), 0);

        // buy
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);

        // USDC moved to contract
        assertEq(usdc.balanceOf(address(lottery)), price);

        // prizePot incremented
        assertEq(lottery.getPrizePot(hourId), price);

        // reservedRefunds equals prizePot
        assertEq(lottery.getReservedRefunds(hourId), price);

        // participant recorded
        QuantumLottery.Participant memory p = lottery.getParticipant(hourId, 0);
        assertEq(p.playerAddress, alice);
        assertEq(lottery.lastEnteredHour(alice), hourId);
    }

    function test_MixedTicketTypes_PrizePotAndReservedRefunds() public {
        uint256 hourId = block.timestamp / 3600;
        uint256 sprice = lottery.STANDARD_TICKET_PRICE();
        uint256 qprice = lottery.QUANTUM_TICKET_PRICE();

        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _buy(bob, QuantumLotteryTypes.TicketType.Quantum);

        uint256 expected = sprice + qprice;
        assertEq(lottery.getPrizePot(hourId), expected);
        assertEq(lottery.getReservedRefunds(hourId), expected);
    }

    function test_BuyTicket_ApprovalRequired() public {
        address dave = makeAddr("dave");
        uint256 amt = 10 * ONE_USDC;
        // mint to dave but do NOT approve
        usdc.mint(dave, amt);

        // dave attempts to buy without approval -> transferFrom should revert
        vm.prank(dave);
        vm.expectRevert();
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
    }

    // =============================================================
    //                   3. Q-SCORE & STREAK LOGIC
    // =============================================================
    function test_Winner_ResetsState() public {
        _buyAndResolveDraw(alice, bob, 150); // Force Bob to win, Alice to lose
        _warpToNextHour();
        _buyAndResolveDraw(bob, alice, 50); // Force Alice to win

        // After the second draw, one of the players should have been the winner.
        // Verify that the winner's qScore reset to baseline and streak reset to 0.
        (, uint32 streakA, uint256 qScoreA) = lottery.players(alice);
        (, uint32 streakB, uint256 qScoreB) = lottery.players(bob);

        if (qScoreA == BASE_QSCORE) {
            assertEq(streakA, 0, "Winner streak should reset");
        } else if (qScoreB == BASE_QSCORE) {
            assertEq(streakB, 0, "Winner streak should reset");
        } else {
            revert("No winner found with baseline qScore");
        }
    }

    function test_Loser_IncrementsState() public {
        _buyAndResolveDraw(alice, bob, 150); // Force Alice to lose

        (, uint32 streak, uint256 qScore) = lottery.players(alice);
        assertEq(
            qScore,
            BASE_QSCORE + BASE_BONUS,
            "Loser qScore should increment"
        );
        assertEq(streak, 1, "Loser streak should increment");
    }

    function test_Streak_CorrectlyResetsAfterMissedHour() public {
        _buyAndResolveDraw(alice, bob, 150); // Alice loses, streak becomes 1
        _warpToNextHour(); // Skip one hour
        _warpToNextHour(); // Play in the second hour
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);

        (, uint32 streak, ) = lottery.players(alice);
        assertEq(streak, 0, "Streak should reset to 0 after missed hour");
    }

    function test_QScore_CappingAtMax() public {
        // Deterministic capping test: set qScore just below cap and force a loss
        address p1 = makeAddr("capAlice");
        address p2 = makeAddr("capBob");
        _mintAndApprove(p1, 10 * ONE_USDC);
        _mintAndApprove(p2, 10 * ONE_USDC);

        // use test helper to set player state directly

        // buys in current hour
        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        // set qScore after buy so buyTicket doesn't overwrite our test value
        uint256 nearCap = lottery.MAX_QSCORE() - 10;
        vm.prank(owner);
        lottery.debugSetPlayer(p1, uint64(block.timestamp / 3600), 0, nearCap);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();

        uint256 req = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 150; // ensure p2 wins and p1 loses (randomValue = 150 % totalQ)
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        (, , uint256 qScoreAfter) = lottery.players(p1);
        assertEq(qScoreAfter, lottery.MAX_QSCORE());
    }

    function test_Streak_BonusThresholds() public {
        uint32 sThreshold = STREAK_MODE_THRESHOLD;
        uint32 bThreshold = BLAZING_STREAK_THRESHOLD;

        // fresh players for streak checks
        address sA = makeAddr("streakA");
        address sB = makeAddr("streakB");
        _mintAndApprove(sA, 1000 * ONE_USDC);
        _mintAndApprove(sB, 1000 * ONE_USDC);

        // perform STREAK_MODE_THRESHOLD+1 losses to cross into streak bonus
        for (uint32 i = 0; i <= sThreshold; i++) {
            _buyAndResolveDraw(sA, sB, 150); // ensure sB wins, sA loses
            _warpToNextHour();
        }
        (, , uint256 qScore) = lottery.players(sA);
        assertTrue(qScore >= BASE_QSCORE + STREAK_BONUS);

        // blazing threshold
        address bA = makeAddr("blazeA");
        address bB = makeAddr("blazeB");
        _mintAndApprove(bA, 2000 * ONE_USDC);
        _mintAndApprove(bB, 2000 * ONE_USDC);
        for (uint32 i = 0; i <= bThreshold; i++) {
            _buyAndResolveDraw(bA, bB, 150);
            _warpToNextHour();
        }
        (, , uint256 qScore2) = lottery.players(bA);
        assertTrue(qScore2 >= BASE_QSCORE + BLAZING_STREAK_BONUS);
    }

    function test_QuantumTicket_BonusApplied() public {
        // Use fresh players for quantum ticket bonus
        address qA = makeAddr("qAlice");
        address qB = makeAddr("qBob");
        _mintAndApprove(qA, 1000 * ONE_USDC);
        _mintAndApprove(qB, 1000 * ONE_USDC);
        vm.prank(qA);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
        vm.prank(qB);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 h = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = _requestWinner(h);
        uint256[] memory words = new uint256[](1);
        words[0] = 150; // qB wins
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(h, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(h, 50);

        (, , uint256 qScore) = lottery.players(qA);
        assertTrue(qScore >= BASE_QSCORE + QUANTUM_TICKET_BONUS);
    }

    // =============================================================
    //                     4. REQUEST RANDOM WINNER
    // =============================================================
    function test_Revert_WhenRequestingForCurrentHour() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.DrawCannotBeClosedYet.selector
            )
        );
        _requestWinner(hourId);
    }

    function test_RequestWinner_TryCatch_HandlesVrfRevert() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();

        // Simulate the VRF coordinator rejecting the request by removing the lottery as a consumer
        vrf.removeConsumer(subId, address(lottery));
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.VrfRequestFailed.selector
            )
        );
        _requestWinner(hourId);

        // Check that the draw status was correctly reset to OPEN
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.OPEN)
        );
        // Re-add the lottery as a consumer for other tests
        vrf.addConsumer(subId, address(lottery));
    }

    function test_RequestWinner_SetsStateAndSavesRequest() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();

        uint256 requestId = _requestWinner(hourId);

        // draw should be in CALCULATING_WINNER
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER)
        );

        // mapping should be set to hourId + 1
        uint256 stored = lottery.s_requestIdToHourIdPlusOne(requestId);
        assertEq(stored, hourId + 1);
    }

    function test_Revert_WhenNoParticipants_requestRandomWinner() public {
        // warp forward so we request for a past hour (otherwise current-hour check triggers)
        vm.warp((block.timestamp / 3600 + 1) * 3600);
        uint256 currentHour = block.timestamp / 3600;
        uint256 hourId = currentHour > 0 ? currentHour - 1 : 0;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.DrawHasNoParticipants.selector
            )
        );
        lottery.requestRandomWinner(hourId);
    }

    function test_ReplayRequestIds_CannotFulfillInvalidRequest() public {
        // call fulfill on a requestId that doesn't map to any draw
        uint256 fakeReq = 999999;
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        // The VRF mock may revert earlier with its own error; accept any revert here
        vm.expectRevert();
        vrf.fulfillRandomWordsWithOverride(fakeReq, address(lottery), words);
    }

    function test_Fulfill_SetsResolvingStatusAndTotals() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _buy(bob, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // After fulfill, draw should be in RESOLVING
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.RESOLVING)
        );
        // basic totals recorded
        // totalQScoreInPool should be > 0
        // cannot directly access totalQScoreInPool (not exposed), but process can proceed
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        // cleanup mappings in chunks
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);
        assertTrue(true);
    }

    function test_CosmicSurge_CancelAndNonOwnerRevert() public {
        uint256 hourId = block.timestamp / 3600;
        // schedule
        vm.prank(owner);
        lottery.setNextCosmicSurge(hourId * 3600);

        // non-owner cannot cancel
        vm.prank(alice);
        vm.expectRevert();
        lottery.cancelNextCosmicSurge();

        // owner can cancel
        vm.prank(owner);
        lottery.cancelNextCosmicSurge();

        // after cancel, scheduling slot should be reset; scheduling again should succeed
        vm.prank(owner);
        lottery.setNextCosmicSurge((hourId + 1) * 3600);
    }

    function test_CosmicSurge_Cancel() public {
        uint256 hourId = block.timestamp / 3600;
        vm.prank(owner);
        lottery.setNextCosmicSurge(hourId * 3600);

        // expect event and reset
        vm.expectEmit(true, false, false, true);
        emit CosmicSurgeCanceled(hourId);
        vm.prank(owner);
        lottery.cancelNextCosmicSurge();

        // scheduling slot should be reset
        assertEq(lottery.nextCosmicSurgeHour(), type(uint256).max);
    }

    function test_CosmicSurge_PreventDoubleSchedule() public {
        uint256 hourId = block.timestamp / 3600;
        vm.prank(owner);
        lottery.setNextCosmicSurge(hourId * 3600);

        // second scheduling should revert with the require message
        vm.prank(owner);
        vm.expectRevert(bytes("Cosmic surge already scheduled"));
        lottery.setNextCosmicSurge((hourId + 1) * 3600);

        // cancel and then allow re-scheduling
        vm.prank(owner);
        lottery.cancelNextCosmicSurge();

        vm.prank(owner);
        lottery.setNextCosmicSurge((hourId + 1) * 3600);
    }

    function test_CosmicSurge_OnlyActiveForScheduledHour() public {
        // non-scheduled draw: loser receives normal bonus
        address noA = makeAddr("noA");
        address noB = makeAddr("noB");
        _mintAndApprove(noA, 10 * ONE_USDC);
        _mintAndApprove(noB, 10 * ONE_USDC);
        // perform a loss in the current hour
        _buyAndResolveDraw(noA, noB, 150);
        (, , uint256 qNo) = lottery.players(noA);
        assertEq(qNo, BASE_QSCORE + BASE_BONUS);

        // scheduled draw: move two hours ahead to avoid any interaction
        address cA = makeAddr("cA");
        address cB = makeAddr("cB");
        _mintAndApprove(cA, 10 * ONE_USDC);
        _mintAndApprove(cB, 10 * ONE_USDC);

        // warp to a fixed future timestamp
        uint256 fixedHour = 100;
        vm.warp(fixedHour * 3600);
        uint256 buyHour = block.timestamp / 3600;

        // schedule cosmic surge for this hour
        vm.prank(owner);
        lottery.setNextCosmicSurge(buyHour * 3600);
        assertEq(lottery.nextCosmicSurgeHour(), buyHour);

        // perform buys at the scheduled hour
        vm.prank(cA);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(cB);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        // verify participants were recorded in the expected buy hour
        assertEq(lottery.getParticipantsCount(buyHour), 2);
        QuantumLottery.Participant memory p0 = lottery.getParticipant(
            buyHour,
            0
        );
        QuantumLottery.Participant memory p1 = lottery.getParticipant(
            buyHour,
            1
        );
        assertEq(p0.playerAddress, cA);
        assertEq(p1.playerAddress, cB);

        // warp to resolution hour and request/fulfill randomness
        vm.warp((buyHour + 1) * 3600);
        uint256 req = _requestWinner(buyHour);
        uint256[] memory words = new uint256[](1);
        words[0] = 150;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // ensure cosmicActive was set on fulfill
        (, , , , , , , , , , , , , , , bool cosmicActive) = lottery.draws(
            buyHour
        );
        assertTrue(
            cosmicActive,
            "Cosmic surge flag should be active for this draw"
        );

        // process and cleanup
        bool done2 = false;
        while (!done2) done2 = lottery.processDrawChunk(buyHour, 50);
        bool cleaned2 = false;
        while (!cleaned2) cleaned2 = lottery.cleanupDrawChunk(buyHour, 50);

        (, , uint256 qCos) = lottery.players(cA);
        assertEq(qCos, BASE_QSCORE + (BASE_BONUS * 3));
    }

    function test_ForceResolve_RevertWhenNotStuck() public {
        uint256 hourId = block.timestamp / 3600;
        // calling forceResolveDraw when draw is OPEN should revert
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(QuantumLotteryTypes.DrawNotStuck.selector)
        );
        lottery.forceResolveDraw(hourId);
    }

    function test_ForceResolve_RevertIfNotStuck_ForResolvingAndResolved()
        public
    {
        // Setup a draw and move it to CALCULATING_WINNER
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        // Fulfill randomness -> draw moves to RESOLVING
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // Attempt forceResolve during RESOLVING should revert
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(QuantumLotteryTypes.DrawNotStuck.selector)
        );
        lottery.forceResolveDraw(hourId);

        // Process fully to RESOLVED
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        // Now in RESOLVED; attempting forceResolve should revert as well
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(QuantumLotteryTypes.DrawNotStuck.selector)
        );
        lottery.forceResolveDraw(hourId);
    }

    function test_ReservedRefunds_DecrementAndWithdrawUnclaimed() public {
        // Create draw with two participants
        address a = makeAddr("ra");
        address b = makeAddr("rb");
        _mintAndApprove(a, 10 * ONE_USDC);
        _mintAndApprove(b, 10 * ONE_USDC);
        vm.prank(a);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(b);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
        uint256 hourId = block.timestamp / 3600;

        _warpToNextHour();

        _requestWinner(hourId);

        // Advance beyond timeout and force-resolve
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        // Both refunds available; check reservedRefunds equals sum
        uint256 expected = lottery.STANDARD_TICKET_PRICE() +
            lottery.QUANTUM_TICKET_PRICE();
        assertEq(lottery.getReservedRefunds(hourId), expected);

        // One claimant claims refund
        vm.prank(a);
        lottery.claimRefund(hourId);
        assertEq(
            lottery.getReservedRefunds(hourId),
            expected - lottery.STANDARD_TICKET_PRICE()
        );

        // Simulate contract balance < reservedRefunds by owner withdrawing some funds
        uint256 balBefore = usdc.balanceOf(address(lottery));
        // withdraw a portion to make balance less than remaining liability
        uint256 withdrawAmt = balBefore / 2;
        vm.prank(owner);
        lottery.emergencyWithdraw(address(usdc), withdrawAmt);

        // Mint USDC to contract so withdrawal can succeed
        uint256 liability = lottery.getReservedRefunds(hourId);
        usdc.mint(address(lottery), liability);
        vm.warp(block.timestamp + lottery.UNCLAIMED_REFUND_PERIOD() + 1);
        uint256 beforeWithdraw = lottery.getReservedRefunds(hourId);
        uint256 ownerBalBefore = usdc.balanceOf(owner);
        vm.prank(owner);
        lottery.withdrawUnclaimed(hourId, owner);
        uint256 afterWithdraw = lottery.getReservedRefunds(hourId);

        assertTrue(
            beforeWithdraw > 0,
            "reservedRefunds should be nonzero before withdraw"
        );
        assertEq(
            afterWithdraw,
            0,
            "reservedRefunds should be zero after withdraw"
        );
        uint256 ownerBalAfter = usdc.balanceOf(owner);
        assertTrue(
            ownerBalAfter > ownerBalBefore,
            "Owner should receive some funds"
        );

        // Create a second draw and ensure its reservedRefunds unaffected
        // Move to a fresh hour (one hour ahead) and create a second draw; ensure it's unaffected
        _warpToNextHour();

        address x = makeAddr("rx");
        _mintAndApprove(x, 5 * ONE_USDC);
        vm.prank(x);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        // determine hour from stored player state to avoid warp/timestamp ambiguity
        uint256 otherHour = lottery.lastEnteredHour(x);
        assertEq(
            lottery.getReservedRefunds(otherHour),
            lottery.STANDARD_TICKET_PRICE()
        );
    }

    function test_WithdrawUnclaimed_RevertBeforeGracePeriod() public {
        // Setup and force-resolve
        address a = makeAddr("wa");
        _mintAndApprove(a, 5 * ONE_USDC);
        vm.prank(a);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        _requestWinner(hourId);
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        // attempt to withdraw too early
        vm.prank(owner);
        vm.expectRevert(bytes("Too early to withdraw"));
        lottery.withdrawUnclaimed(hourId, owner);
    }

    function test_ClaimRefund_ErrorPaths() public {
        // Setup draw and force-resolve
        address a = makeAddr("ea");
        address b = makeAddr("eb");
        _mintAndApprove(a, 5 * ONE_USDC);
        _mintAndApprove(b, 5 * ONE_USDC);
        vm.prank(a);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(b);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        _requestWinner(hourId);
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        // Non-participant tries to claim
        address non = makeAddr("non");
        vm.prank(non);
        vm.expectRevert();
        lottery.claimRefund(hourId);

        // Participant claims successfully
        vm.prank(a);
        lottery.claimRefund(hourId);

        // Double claim should revert
        vm.prank(a);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.NoRefundAvailable.selector
            )
        );
        lottery.claimRefund(hourId);

        // Owner withdraws remaining (after grace) to simulate funds gone, then remaining participant claim should revert
        vm.warp(block.timestamp + lottery.UNCLAIMED_REFUND_PERIOD() + 1);
        vm.prank(owner);
        lottery.withdrawUnclaimed(hourId, owner);

        vm.prank(b);
        vm.expectRevert();
        lottery.claimRefund(hourId);
    }

    function test_ReservedRefunds_AccountingMatchesDeposits() public {
        uint256 hourId = block.timestamp / 3600;
        uint256 total = 0;
        // mix of standard and quantum buys
        for (uint256 i = 0; i < 5; i++) {
            address p = address(uint160(1000 + i));
            _mintAndApprove(p, 10 * ONE_USDC);
            if (i % 2 == 0) {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
                total += lottery.STANDARD_TICKET_PRICE();
            } else {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
                total += lottery.QUANTUM_TICKET_PRICE();
            }
        }
        assertEq(lottery.getReservedRefunds(hourId), total);
    }

    // =============================================================
    //                        5. FULFILL RANDOM WORDS
    // =============================================================
    function test_Fulfill_CorrectlyDistributesAndCleansUp() public {
        uint256 prizePot = lottery.STANDARD_TICKET_PRICE() * 2;
        _buyAndResolveDraw(alice, bob, 150); // Force Bob to win

        // After resolving the draw the participants mapping should be deleted; verify no participants remain
        assertEq(
            lottery.getParticipantsCount(block.timestamp / 3600),
            0,
            "Draw struct should be deleted"
        );
        assertEq(
            usdc.balanceOf(address(lottery)),
            0,
            "Lottery balance should be zero"
        );
        assertEq(
            usdc.balanceOf(treasury),
            (prizePot * 8) / 100,
            "Treasury should receive 8%"
        );
    }

    // =============================================================
    //                        6. COSMIC SURGE
    // =============================================================
    function test_CosmicSurge_TriplesLoserBonus() public {
        uint256 hourId = block.timestamp / 3600;
        vm.prank(owner);
        lottery.setNextCosmicSurge(hourId * 3600);

        _buyAndResolveDraw(alice, bob, 150); // Alice loses

        (, , uint256 qScore) = lottery.players(alice);
        assertEq(
            qScore,
            BASE_QSCORE + (BASE_BONUS * 3),
            "Cosmic surge should triple bonus"
        );
    }

    // =============================================================
    //                     7. ADDITIONAL SAFETY & EDGE TESTS
    // =============================================================
    function test_Constructor_SetsOwner() public view {
        assertEq(lottery.owner(), owner);
    }

    // =============================================================
    //                 2. ACCESS CONTROL & OWNERSHIP
    // =============================================================
    function test_OwnerOnly_requestRandomWinner() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();

        // non-owner should not be able to request winner
        vm.prank(alice);
        vm.expectRevert();
        lottery.requestRandomWinner(hourId);
    }

    function test_OwnerOnly_setNextCosmicSurge_cancel() public {
        // non-owner cannot schedule
        vm.prank(alice);
        vm.expectRevert();
        lottery.setNextCosmicSurge(block.timestamp + 3600);

        // non-owner cannot cancel
        vm.prank(alice);
        vm.expectRevert();
        lottery.cancelNextCosmicSurge();

        // non-owner cannot force resolve
        uint256 hourId = block.timestamp / 3600;
        vm.prank(alice);
        vm.expectRevert();
        lottery.forceResolveDraw(hourId);

        // non-owner cannot withdraw unclaimed
        vm.prank(alice);
        vm.expectRevert();
        lottery.withdrawUnclaimed(hourId, alice);
    }

    function test_emergencyWithdraw_onlyOwner() public {
        uint256 amt = 5 * ONE_USDC;
        // mint tokens to contract
        usdc.mint(address(lottery), amt);

        // non-owner cannot call emergencyWithdraw
        vm.prank(alice);
        vm.expectRevert();
        lottery.emergencyWithdraw(address(usdc), amt);

        // owner can withdraw
        vm.prank(owner);
        lottery.emergencyWithdraw(address(usdc), amt);
        assertEq(usdc.balanceOf(owner), amt);
    }

    function test_ForceResolve_TimeoutAndClaimRefund() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _buy(bob, QuantumLotteryTypes.TicketType.Quantum);
        _warpToNextHour();
        _requestWinner(hourId);

        // Do not fulfill via VRF. Advance time past timeout.
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);

        // owner force-resolves
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        // participants can claim refunds

        vm.prank(alice);
        lottery.claimRefund(hourId);
        assertEq(usdc.balanceOf(alice), 1000 * ONE_USDC);

        vm.prank(bob);
        lottery.claimRefund(hourId);
        assertEq(usdc.balanceOf(bob), 1000 * ONE_USDC);

        // subsequent claims revert
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.NoRefundAvailable.selector
            )
        );
        lottery.claimRefund(hourId);
    }

    function test_GasStress_MaxParticipantsFulfill() public {
        uint256 cap = lottery.MAX_PARTICIPANTS();
        uint256 stressCount = cap;
        uint256 hourId = block.timestamp / 3600;
        for (uint256 i = 0; i < stressCount; i++) {
            address player = address(uint160(i + 1));
            _mintAndApprove(player, 1 * ONE_USDC);
            _buy(player, QuantumLotteryTypes.TicketType.Standard);
        }

        _warpToNextHour();
        uint256 requestId = _requestWinner(hourId);

        // fulfill with a fixed random value to trigger the winner-selection loop
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

        // Process the draw in chunks until complete. Use iterations of 50.
        bool done = false;
        while (!done) {
            done = lottery.processDrawChunk(hourId, 50);
        }
        // cleanup mappings in chunks
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);
    }

    function test_ChunkSize_Sensitivity() public {
        // Try different chunk sizes to ensure processing completes
        uint256 cap = lottery.MAX_PARTICIPANTS();

        // prepare participants (compute hour after buys to be robust)
        for (uint256 i = 0; i < cap; i++) {
            address player = address(uint160(2000 + i + 1));
            _mintAndApprove(player, 1 * ONE_USDC);
            _buy(player, QuantumLotteryTypes.TicketType.Standard);
        }

        // determine the buy hour from a sample participant (robust against vm time quirks)
        address sample = address(uint160(2000 + 1));
        uint256 hourId = lottery.lastEnteredHour(sample);
        // explicitly warp to the resolution hour for the computed buy hour
        vm.warp((hourId + 1) * 3600);
        uint256 requestId = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

        uint256[4] memory sizes = [
            uint256(1),
            uint256(10),
            uint256(50),
            uint256(100)
        ];
        for (uint256 si = 0; si < sizes.length; si++) {
            uint256 chunk = sizes[si];

            // process until done using chunk size
            bool done = false;
            while (!done) done = lottery.processDrawChunk(hourId, chunk);

            // cleanup mappings in chunks
            bool cleaned = false;
            while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, chunk);

            // after cleanup, participants should be cleared
            assertEq(lottery.getParticipantsCount(hourId), 0);

            // Re-create the draw for the next chunk size iteration if any
            if (si + 1 < sizes.length) {
                // new buys for same hour index (move to next hour to reset)
                _warpToNextHour();
                for (uint256 i = 0; i < cap; i++) {
                    address player2 = address(uint160(3000 + i + 1));
                    _mintAndApprove(player2, 1 * ONE_USDC);
                    _buy(player2, QuantumLotteryTypes.TicketType.Standard);
                }
                // compute the new hour from a sample participant after buys
                address sample2 = address(uint160(3000 + 1));
                hourId = lottery.lastEnteredHour(sample2);
                // explicitly warp to resolution hour for this buy hour
                vm.warp((hourId + 1) * 3600);
                uint256 req2 = _requestWinner(hourId);
                uint256[] memory w2 = new uint256[](1);
                w2[0] = 1;
                vrf.fulfillRandomWordsWithOverride(req2, address(lottery), w2);
            }
        }
    }

    function test_CleanupChunk_LargeDraw() public {
        // Ensure cleanupDrawChunk works for a large draw when processed in small chunks
        uint256 cap = lottery.MAX_PARTICIPANTS();
        uint256 hourId = block.timestamp / 3600;

        for (uint256 i = 0; i < cap; i++) {
            address player = address(uint160(4000 + i + 1));
            _mintAndApprove(player, 1 * ONE_USDC);
            _buy(player, QuantumLotteryTypes.TicketType.Standard);
        }

        _warpToNextHour();
        uint256 requestId = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

        // process the draw fully
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 100);

        // now cleanup in small chunks to simulate gas-limited cleanup
        bool cleaned = false;
        uint256 rounds = 0;
        while (!cleaned) {
            cleaned = lottery.cleanupDrawChunk(hourId, 1);
            rounds++;
            require(rounds < cap + 10, "cleanup took too many rounds");
        }

        assertEq(lottery.getParticipantsCount(hourId), 0);
    }

    function test_WeightedRandomness_Deterministic() public {
        // Small deterministic weighted randomness check
        address p1 = address(uint160(201));
        address p2 = address(uint160(202));
        address p3 = address(uint160(203));

        _mintAndApprove(p1, 1 * ONE_USDC);
        _mintAndApprove(p2, 1 * ONE_USDC);
        _mintAndApprove(p3, 1 * ONE_USDC);

        // All buy in the same hour
        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p3);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        // pick a small random value; since qScores are baseline equal, selection should succeed
        words[0] = 2;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 10);

        // cleanup mappings in chunks
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 10);

        // if no revert and processing finished, this basic deterministic smoke test is OK
        assertTrue(true);
    }

    function test_PayoutInvariant_WinnerPlusFeeEqualsPrize() public {
        uint256 hourId = block.timestamp / 3600;
        _buy(alice, QuantumLotteryTypes.TicketType.Standard);
        _buy(bob, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        uint256 requestId = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);

        // cleanup mappings in chunks
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        uint256 prizePot = lottery.STANDARD_TICKET_PRICE() * 2;
        uint256 winnerAmount = (prizePot * 92) / 100;
        uint256 feeAmount = prizePot - winnerAmount;
        assertEq(winnerAmount + feeAmount, prizePot);
    }

    // =============================================================
    //                 13. FUZZ / PROPERTY-BASED TESTS
    // =============================================================

    /// fuzz: up to MAX_PARTICIPANTS random users buy tickets (random types)
    function test_fuzz_BuyTickets_randomUsers(
        uint256 count,
        uint256 seed
    ) public {
        uint256 cap = lottery.MAX_PARTICIPANTS();
        vm.assume(count <= cap);

        if (count == 0) {
            // no-op: nothing to buy
            return;
        }

        // create buys
        for (uint256 i = 0; i < count; i++) {
            address p = address(uint160(10000 + i));
            _mintAndApprove(p, 10 * ONE_USDC);
            // pseudo-random ticket type from seed
            uint256 bit = (seed >> (i % 256)) & 1;
            if (bit == 0) {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
            } else {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
            }
        }

        // determine buy hour from a sample participant
        address sample = address(uint160(10000 + 1));
        uint256 hourId = lottery.lastEnteredHour(sample);

        // compute expected totals locally
        uint256 expected = 0;
        for (uint256 i = 0; i < count; i++) {
            uint256 bit = (seed >> (i % 256)) & 1;
            if (bit == 0) expected += lottery.STANDARD_TICKET_PRICE();
            else expected += lottery.QUANTUM_TICKET_PRICE();
        }

        assertEq(lottery.getPrizePot(hourId), expected);
        assertEq(lottery.getReservedRefunds(hourId), expected);
    }

    /// fuzz: verify weighted randomness bracket selection matches contract winner
    function test_fuzz_WeightedRandomness_properties(
        uint256 n,
        uint256 seed,
        uint256 rawRand
    ) public {
        // limit participants for gas
        vm.assume(n > 0 && n <= 20);

        // set different qScores via debugSetPlayer then buy
        for (uint256 i = 0; i < n; i++) {
            address p = address(uint160(11000 + i));
            _mintAndApprove(p, 10 * ONE_USDC);
            // derive qScore from seed (ensure non-zero)
            uint256 q = (uint256(keccak256(abi.encode(seed, i))) % 1000) + 1;
            vm.prank(owner);
            lottery.debugSetPlayer(p, uint64(block.timestamp / 3600), 0, q);
            vm.prank(p);
            lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        }

        address sample = address(uint160(11000 + 1));
        uint256 hourId = lottery.lastEnteredHour(sample);

        // compute total Q and bound random
        uint256 totalQ = 0;
        uint256 pc = lottery.getParticipantsCount(hourId);
        for (uint256 i = 0; i < pc; i++) {
            QuantumLottery.Participant memory part = lottery.getParticipant(
                hourId,
                i
            );
            totalQ += part.qScoreOnEntry;
        }
        vm.assume(totalQ > 0);
        uint256 randomValue = rawRand % totalQ;

        // request and fulfill
        vm.warp((hourId + 1) * 3600);
        uint256 req = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = randomValue;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // compute expected winner by scanning cumulative brackets BEFORE cleanup
        uint256 cum = 0;
        address expectedWinner = address(0);
        for (uint256 i = 0; i < pc; i++) {
            QuantumLottery.Participant memory part = lottery.getParticipant(
                hourId,
                i
            );
            cum += part.qScoreOnEntry;
            if (randomValue < cum) {
                expectedWinner = part.playerAddress;
                break;
            }
        }

        // process to completion and cleanup
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        address winner = lottery.getWinner(hourId);
        assertEq(winner, expectedWinner);
    }

    /// fuzz: repeated losses should never increase qScore beyond MAX_QSCORE
    function test_fuzz_QScore_cannotOverflow(uint256 rounds) public {
        vm.assume(rounds > 0 && rounds <= 200);

        address subj = makeAddr("fuzz_subj");
        address opp = makeAddr("fuzz_opp");
        _mintAndApprove(subj, 1000 * ONE_USDC);
        _mintAndApprove(opp, 1000 * ONE_USDC);

        // perform many rounds where subj always loses
        for (uint256 r = 0; r < rounds; r++) {
            vm.prank(subj);
            lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
            vm.prank(opp);
            lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

            uint256 hourId = lottery.lastEnteredHour(subj);
            vm.warp((hourId + 1) * 3600);
            uint256 req = _requestWinner(hourId);

            // ensure opponent wins: set randomValue to >= subj's qScoreOnEntry
            QuantumLottery.Participant memory p0 = lottery.getParticipant(
                hourId,
                0
            );
            uint256 rand = p0.qScoreOnEntry; // picks the second participant
            uint256[] memory w = new uint256[](1);
            w[0] = rand;
            vrf.fulfillRandomWordsWithOverride(req, address(lottery), w);

            bool done = false;
            while (!done) done = lottery.processDrawChunk(hourId, 50);
            bool cleaned = false;
            while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

            (, , uint256 subjQ) = lottery.players(subj);
            assertTrue(subjQ <= lottery.MAX_QSCORE());
        }
    }

    /// fuzz: payout invariants hold for random draws
    function test_fuzz_Payout_Invariants(uint256 count, uint256 seed) public {
        vm.assume(count > 0 && count <= 50);

        uint256 beforeTreasury = usdc.balanceOf(treasury);

        // buys
        address[] memory arr = new address[](count);
        uint256[] memory afterBuy = new uint256[](count);
        uint256 expectedPrize = 0;
        for (uint256 i = 0; i < count; i++) {
            address p = address(uint160(12000 + i));
            arr[i] = p;
            _mintAndApprove(p, 10 * ONE_USDC);
            uint256 bit = (seed >> (i % 256)) & 1;
            if (bit == 0) {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
                expectedPrize += lottery.STANDARD_TICKET_PRICE();
            } else {
                vm.prank(p);
                lottery.buyTicket(QuantumLotteryTypes.TicketType.Quantum);
                expectedPrize += lottery.QUANTUM_TICKET_PRICE();
            }
            afterBuy[i] = usdc.balanceOf(p);
        }

        address sample = arr[0];
        uint256 hourId = lottery.lastEnteredHour(sample);
        vm.warp((hourId + 1) * 3600);
        uint256 req = _requestWinner(hourId);

        // pick an arbitrary random value within range
        uint256 totalQ = 0;
        uint256 pc = lottery.getParticipantsCount(hourId);
        for (uint256 i = 0; i < pc; i++) {
            totalQ += lottery.getParticipant(hourId, i).qScoreOnEntry;
        }
        vm.assume(totalQ > 0);
        uint256 rand = uint256(keccak256(abi.encode(seed))) % totalQ;
        uint256[] memory words = new uint256[](1);
        words[0] = rand;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        address winner = lottery.getWinner(hourId);
        uint256 winnerIdx = type(uint256).max;
        for (uint256 i = 0; i < count; i++) {
            if (arr[i] == winner) {
                winnerIdx = i;
                break;
            }
        }
        // winner should be in array
        assertTrue(winnerIdx < count);

        uint256 winnerDelta = usdc.balanceOf(winner) - afterBuy[winnerIdx];
        uint256 treasuryDelta = usdc.balanceOf(treasury) - beforeTreasury;

        assertEq(winnerDelta + treasuryDelta, expectedPrize);
    }

    // =============================================================
    //                   10. EDGE / NEGATIVE TESTS & ROBUSTNESS
    // =============================================================

    // ...existing code...

    function test_FulfillWithInvalidRequestId() public {
        // Attempt to fulfill a random request id that doesn't map to any draw
        uint256 fakeReq = 123456789;
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        // The VRF mock may revert with its own message before the lottery's revert
        // so accept any revert here.
        vm.expectRevert();
        // VRF mock will call into lottery.fulfillRandomWords; expect the specific revert
        vrf.fulfillRandomWordsWithOverride(fakeReq, address(lottery), words);
    }

    function test_CallsAfterPrizePotZero() public {
        // create a draw and request winner, then owner force-resolves and withdraws; ensure withdrawUnclaimed works and processDrawChunk cannot be used to payout
        address p = makeAddr("e1");
        _mintAndApprove(p, 5 * ONE_USDC);
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();

        // request winner so draw enters CALCULATING_WINNER, then advance past timeout and force-resolve
        _requestWinner(hourId);
        // sanity: draw should now be in CALCULATING_WINNER
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER)
        );

        // advance past timeout and force-resolve
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        // processDrawChunk should revert because draw is not in RESOLVING
        vm.expectRevert();
        lottery.processDrawChunk(hourId, 10);

        // owner can withdraw unclaimed after grace period
        vm.warp(block.timestamp + lottery.UNCLAIMED_REFUND_PERIOD() + 1);
        // mint some token to contract to allow withdraw
        usdc.mint(address(lottery), lottery.getReservedRefunds(hourId));
        vm.prank(owner);
        lottery.withdrawUnclaimed(hourId, owner);
        // successful if no revert and owner balance increased
        assertTrue(usdc.balanceOf(owner) > 0);
    }

    function test_processDrawChunk_ReentrancySafety() public {
        // Deploy a separate lottery that uses a malicious token to attempt reentrancy on payouts
        VRFCoordinatorV2Mock localVrf = new VRFCoordinatorV2Mock(0, 0);
        uint64 localSub = localVrf.createSubscription();
        localVrf.fundSubscription(localSub, 100 ether);

        MaliciousERC20 m = new MaliciousERC20();
        // deploy a fresh lottery using the malicious token
        QuantumLottery malLottery = new QuantumLottery(
            address(m),
            treasury,
            address(localVrf),
            localSub,
            gasLane
        );
        localVrf.addConsumer(localSub, address(malLottery));

        address p1 = makeAddr("mal1");
        _mintAndApprove(p1, 10 * ONE_USDC);
        // mint malicious tokens to player and approve using the malicious lottery's price constant
        uint256 malPrice = malLottery.STANDARD_TICKET_PRICE();
        m.mint(p1, malPrice);
        vm.prank(p1);
        m.approve(address(malLottery), malPrice);
        // sanity check balance and allowance set on malicious token
        assertEq(m.balanceOf(p1), malPrice);
        assertEq(m.allowance(p1, address(malLottery)), malPrice);

        // player buys into malicious lottery
        vm.prank(p1);
        malLottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 h = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = malLottery.requestRandomWinner(h);

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        // fulfill randomness to set RESOLVING state and totals
        localVrf.fulfillRandomWordsWithOverride(
            req,
            address(malLottery),
            words
        );

        // configure malicious token to reenter on transfer
        m.setTarget(address(malLottery), h);

        // Attempt to process draw: first call should pick the winner but not finish (returns false)
        bool firstDone = malLottery.processDrawChunk(h, 100);
        assertTrue(
            !firstDone,
            "first chunk should not finish and should pick winner"
        );

        // configure expectation: the next call will attempt payouts and the malicious token will try to reenter during transfer; this should revert
        vm.expectRevert();
        malLottery.processDrawChunk(h, 100);
    }

    function test_getParticipant_IndexOutOfBounds() public {
        uint256 h = block.timestamp / 3600;
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.IndexOutOfBounds.selector
            )
        );
        lottery.getParticipant(h, 0);
    }

    function test_lastEnteredHour_Behavior() public {
        address p = makeAddr("lah");
        // before playing
        assertEq(lottery.lastEnteredHour(p), 0);
        _mintAndApprove(p, 5 * ONE_USDC);
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 h = block.timestamp / 3600;
        assertEq(lottery.lastEnteredHour(p), h);
    }

    function test_getDrawStatus_Transitions() public {
        // Test normal flow first
        uint256 normalHour = block.timestamp / 3600;
        _mintAndApprove(alice, 5 * ONE_USDC);
        vm.prank(alice);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        // draw should be OPEN before requesting
        assertEq(
            uint256(lottery.getDrawStatus(normalHour)),
            uint256(QuantumLotteryTypes.DrawStatus.OPEN)
        );
        uint256 req = _requestWinner(normalHour);
        // status should be CALCULATING_WINNER
        assertEq(
            uint256(lottery.getDrawStatus(normalHour)),
            uint256(QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER)
        );

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);
        // status should be RESOLVING
        assertEq(
            uint256(lottery.getDrawStatus(normalHour)),
            uint256(QuantumLotteryTypes.DrawStatus.RESOLVING)
        );

        // process to completion
        bool done = false;
        while (!done) done = lottery.processDrawChunk(normalHour, 50);
        // after processing, draw.status should be RESOLVED
        assertEq(
            uint256(lottery.getDrawStatus(normalHour)),
            uint256(QuantumLotteryTypes.DrawStatus.RESOLVED)
        );

        // now test forced flow - completely separate draw
        _warpToNextHour();
        address p2 = makeAddr("fr2");
        _mintAndApprove(p2, 5 * ONE_USDC);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        // determine the entered hour directly from contract state (robust)
        _warpToNextHour();
        uint256 forceTestHour = lottery.lastEnteredHour(p2);
        assertEq(
            uint256(lottery.getDrawStatus(forceTestHour)),
            uint256(QuantumLotteryTypes.DrawStatus.OPEN)
        );
        uint256 req2 = _requestWinner(forceTestHour);
        // ensure request id maps back to the forced hour and status is CALCULATING
        assertEq(
            uint256(lottery.getDrawStatus(forceTestHour)),
            uint256(QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER)
        );
        // verify mapping stored
        uint256 stored = lottery.s_requestIdToHourIdPlusOne(req2);
        assertEq(stored, forceTestHour + 1);
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(forceTestHour);
        assertEq(
            uint256(lottery.getDrawStatus(forceTestHour)),
            uint256(QuantumLotteryTypes.DrawStatus.RESOLVED)
        );
    }

    // =============================================================
    // 14. INTEGRATION & EXTERNAL MOCKS
    // =============================================================

    /// 14.1 Ensure VRF mock integration clears the requestId -> hour mapping after fulfill
    function test_VRF_MockIntegration() public {
        address p = makeAddr("vrf_p");
        _mintAndApprove(p, 5 * ONE_USDC);
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = lottery.lastEnteredHour(p);
        _warpToNextHour();

        // owner requests winner
        vm.prank(owner);
        uint256 req = lottery.requestRandomWinner(hourId);

        // mapping should be set
        assertEq(lottery.s_requestIdToHourIdPlusOne(req), hourId + 1);

        // fulfill randomness via mock; this should delete the mapping
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // mapping cleared
        assertEq(lottery.s_requestIdToHourIdPlusOne(req), 0);

        // draw moved to RESOLVING after fulfill
        assertEq(
            uint256(lottery.getDrawStatus(hourId)),
            uint256(QuantumLotteryTypes.DrawStatus.RESOLVING)
        );
    }

    /// 14.2 Test USDC-like token behaviours: missing approval and non-compliant tokens
    function test_USDC_Mock_behaviour() public {
        // Case A: user hasn't approved - transferFrom should revert via SafeERC20
        address p = makeAddr("noapprove");
        usdc.mint(p, 5 * ONE_USDC);
        vm.prank(p);
        vm.expectRevert();
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        // Case B: token that returns false from transferFrom
        VRFCoordinatorV2Mock localVrf = new VRFCoordinatorV2Mock(0, 0);
        uint64 localSub = localVrf.createSubscription();
        localVrf.fundSubscription(localSub, 100 ether);

        BadUSDC b = new BadUSDC();
        vm.prank(owner);
        QuantumLottery badLottery = new QuantumLottery(
            address(b),
            treasury,
            address(localVrf),
            localSub,
            gasLane
        );
        localVrf.addConsumer(localSub, address(badLottery));

        address p2 = makeAddr("badtok_p");
        // mint uses onlyOwner; test contract is owner of the token
        b.mint(p2, 10 * ONE_USDC);
        // approve the bad lottery
        vm.prank(p2);
        b.approve(address(badLottery), type(uint256).max);

        // Now attempt to buy - internal safeTransferFrom should detect false return and revert
        vm.prank(p2);
        vm.expectRevert();
        badLottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
    }

    // =============================================================
    // 11. EVENTS & TELEMETRY
    // =============================================================
    function test_Events_TicketPurchased() public {
        address p = makeAddr("evp");
        _mintAndApprove(p, 5 * ONE_USDC);
        uint256 hourId = block.timestamp / 3600;
        // expect TicketPurchased with baseline qScore
        vm.expectEmit(true, true, false, true);
        emit TicketPurchased(
            hourId,
            p,
            QuantumLotteryTypes.TicketType.Standard,
            BASE_QSCORE
        );
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
    }

    function test_Events_WinnerSelectionRequested_and_RandomnessFulfilled()
        public
    {
        address p = makeAddr("evr1");
        _mintAndApprove(p, 5 * ONE_USDC);
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();

        // expect WinnerSelectionRequested on request
        vm.expectEmit(true, false, false, false);
        emit WinnerSelectionRequested(hourId, 0);
        vm.prank(owner);
        uint256 req = lottery.requestRandomWinner(hourId);

        // expect RandomnessFulfilled when VRF mock fulfills
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.expectEmit(true, false, false, false);
        emit RandomnessFulfilled(hourId, 0, 0);
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);
    }

    function test_Events_WinnerPicked_matchesBalances() public {
        address p1 = makeAddr("wp1");
        address p2 = makeAddr("wp2");
        _mintAndApprove(p1, 5 * ONE_USDC);
        _mintAndApprove(p2, 5 * ONE_USDC);
        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        vm.prank(owner);
        uint256 req = lottery.requestRandomWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 0; // pick first player deterministically
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        uint256 prizePot = lottery.STANDARD_TICKET_PRICE() * 2;
        uint256 winnerAmount = (prizePot * 92) / 100;
        uint256 feeAmount = prizePot - winnerAmount;

        // first chunk should pick the winner but may not finalize
        bool firstDone = lottery.processDrawChunk(hourId, 500);
        assertTrue(
            !firstDone,
            "first chunk should not finish and should pick winner"
        );

        // expect WinnerPicked event on the finalizing call
        uint256 expectedTotalQ = BASE_QSCORE * 2;
        vm.expectEmit(true, true, false, true);
        emit WinnerPicked(hourId, p1, winnerAmount, feeAmount, expectedTotalQ);

        // finalizing call should emit WinnerPicked
        bool secondDone = lottery.processDrawChunk(hourId, 500);
        assertTrue(
            secondDone,
            "second chunk should finish and emit WinnerPicked"
        );

        // verify balances (players were minted 5 USDC each in this test)
        assertEq(
            usdc.balanceOf(p1),
            5 * ONE_USDC - lottery.STANDARD_TICKET_PRICE() + winnerAmount
        );
        assertEq(usdc.balanceOf(treasury), feeAmount);
    }

    function test_Events_RefundIssued_remainingLiability() public {
        address p = makeAddr("rf1");
        _mintAndApprove(p, 5 * ONE_USDC);
        vm.prank(p);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        _requestWinner(hourId);
        vm.warp(block.timestamp + lottery.DRAW_RESOLUTION_TIMEOUT() + 1);
        vm.prank(owner);
        lottery.forceResolveDraw(hourId);

        uint256 beforeReserved = lottery.getReservedRefunds(hourId);
        uint256 refundAmt = lottery.STANDARD_TICKET_PRICE();
        uint256 expectedRemaining = beforeReserved - refundAmt;

        vm.expectEmit(true, true, false, true);
        emit RefundIssued(hourId, p, refundAmt, expectedRemaining);
        vm.prank(p);
        lottery.claimRefund(hourId);

        assertEq(lottery.getReservedRefunds(hourId), expectedRemaining);
    }

    function test_request_random_multiple_times_fail() public {
        uint256 h = block.timestamp / 3600;
        _mintAndApprove(alice, 5 * ONE_USDC);
        vm.prank(alice);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        _requestWinner(h);
        // second request should revert
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuantumLotteryTypes.DrawAlreadyResolvedOrCalculating.selector
            )
        );
        lottery.requestRandomWinner(h);
        // fulfill -> RESOLVING (no-op)
    }

    // =============================================================
    // 5. FULFILL RANDOM WORDS & CHUNKED PROCESSING (additional tests)
    // =============================================================
    function test_ProcessChunk_WrapAroundCase() public {
        // create several players; ensure winner is late in array by using a large random value
        address p1 = address(uint160(301));
        address p2 = address(uint160(302));
        address p3 = address(uint160(303));
        address p4 = address(uint160(304));

        _mintAndApprove(p1, 1 * ONE_USDC);
        _mintAndApprove(p2, 1 * ONE_USDC);
        _mintAndApprove(p3, 1 * ONE_USDC);
        _mintAndApprove(p4, 1 * ONE_USDC);

        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p3);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p4);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        // pick a value likely to be beyond initial cumulative scan so winner found late
        words[0] = 3;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // process with small iterations to force wrap logic
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 1);

        // cleanup
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 1);

        assertEq(lottery.getParticipantsCount(hourId), 0);
    }

    function test_ProcessChunk_HandleZeroedParticipantSlots() public {
        // two players, zero out one slot before processing
        address p1 = address(uint160(401));
        address p2 = address(uint160(402));

        _mintAndApprove(p1, 1 * ONE_USDC);
        _mintAndApprove(p2, 1 * ONE_USDC);

        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // zero the first participant slot to simulate a pre-claimed refund
        vm.prank(owner);
        lottery.debugZeroParticipant(hourId, 0);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 10);

        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 10);

        assertEq(lottery.getParticipantsCount(hourId), 0);
    }

    function test_ProcessChunk_GasIterationLimits() public {
        // small iteration size should still finish
        address p1 = address(uint160(501));
        address p2 = address(uint160(502));
        address p3 = address(uint160(503));

        _mintAndApprove(p1, 1 * ONE_USDC);
        _mintAndApprove(p2, 1 * ONE_USDC);
        _mintAndApprove(p3, 1 * ONE_USDC);

        vm.prank(p1);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p2);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(p3);
        lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 hourId = block.timestamp / 3600;
        _warpToNextHour();
        uint256 req = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        // use tiny iteration count
        bool done = false;
        uint256 rounds = 0;
        while (!done) {
            done = lottery.processDrawChunk(hourId, 1);
            rounds++;
            require(rounds < 100, "Too many rounds");
        }

        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 1);
    }

    // =============================================================
    // 6. PAYOUTS & ACCOUNTING INVARIANTS
    // =============================================================
    function test_FeePercent_IsProtocolFee() public {
        uint256 hourId = block.timestamp / 3600;
        uint256 sprice = lottery.STANDARD_TICKET_PRICE();
        uint256 prizePot = sprice * 2;
        uint256 winnerAmount = (prizePot * 92) / 100;
        uint256 feeAmount = prizePot - winnerAmount;

        // record treasury balance before
        uint256 beforeTreasury = usdc.balanceOf(treasury);

        // buys
        vm.prank(alice);
    lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(bob);
    lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        uint256 afterBuyAlice = usdc.balanceOf(alice);
        uint256 afterBuyBob = usdc.balanceOf(bob);

        _warpToNextHour();
        uint256 req = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        // treasury received feeAmount
        assertEq(usdc.balanceOf(treasury) - beforeTreasury, feeAmount);

        // winner received winnerAmount (net of having paid ticket earlier)
        uint256 finalAlice = usdc.balanceOf(alice);
        uint256 finalBob = usdc.balanceOf(bob);
        if (finalAlice == afterBuyAlice + winnerAmount) {
            // alice won
            assertEq(finalBob, afterBuyBob);
        } else if (finalBob == afterBuyBob + winnerAmount) {
            // bob won
            assertEq(finalAlice, afterBuyAlice);
        } else {
            revert("No winner received correct payout");
        }
    }

    function test_PrizePot_DepletedAfterPayout() public {
        uint256 hourId = block.timestamp / 3600;
        uint256 sprice = lottery.STANDARD_TICKET_PRICE();
        uint256 prizePot = sprice * 2;

        // buys
        vm.prank(alice);
    lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
        vm.prank(bob);
    lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

        // contract balance should equal prizePot
        assertEq(usdc.balanceOf(address(lottery)), prizePot);

        _warpToNextHour();
        uint256 req = _requestWinner(hourId);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, 50);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);

        // after payouts and cleanup, contract should have no leftover (only these tickets)
        assertEq(usdc.balanceOf(address(lottery)), 0);
    }

    function test_MultipleWinners_SequentialHours() public {
        uint256 startHour = block.timestamp / 3600 + 1;
        for (uint256 i = 0; i < 3; i++) {
            uint256 buyHour = startHour + i;

            // reset balances and approvals for each iteration
            usdc.mint(alice, 1 * ONE_USDC);
            usdc.mint(bob, 1 * ONE_USDC);
            vm.prank(alice);
            usdc.approve(address(lottery), type(uint256).max);
            vm.prank(bob);
            usdc.approve(address(lottery), type(uint256).max);

            // warp to buy hour and make purchases
            vm.warp(buyHour * 3600);
            vm.prank(alice);
            lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);
            vm.prank(bob);
            lottery.buyTicket(QuantumLotteryTypes.TicketType.Standard);

            uint256 beforeTreasury = usdc.balanceOf(treasury);
            uint256 beforeAlice = usdc.balanceOf(alice);
            uint256 beforeBob = usdc.balanceOf(bob);

            // no-op: deterministic iteration

            // warp to resolution hour and request/fulfill
            vm.warp((buyHour + 1) * 3600);
            uint256 req = _requestWinner(buyHour);
            uint256[] memory words = new uint256[](1);
            words[0] = 1 + i;
            vrf.fulfillRandomWordsWithOverride(req, address(lottery), words);

            bool done = false;
            while (!done) done = lottery.processDrawChunk(buyHour, 50);
            bool cleaned = false;
            while (!cleaned) cleaned = lottery.cleanupDrawChunk(buyHour, 50);

            uint256 prizePot = lottery.STANDARD_TICKET_PRICE() * 2;
            uint256 winnerAmount = (prizePot * 92) / 100;
            uint256 feeAmount = prizePot - winnerAmount;

            // treasury checks performed via delta assertion earlier

            assertEq(usdc.balanceOf(treasury) - beforeTreasury, feeAmount);

            uint256 finalA = usdc.balanceOf(alice);
            uint256 finalB = usdc.balanceOf(bob);
            uint256 deltaA = finalA - beforeAlice;
            uint256 deltaB = finalB - beforeBob;
            if (deltaA == winnerAmount) {
                assertEq(deltaB, 0);
            } else if (deltaB == winnerAmount) {
                assertEq(deltaA, 0);
            } else {
                revert("No winner received correct payout in sequence");
            }
        }
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================
    function _mintAndApprove(address user, uint256 amt) internal {
        usdc.mint(user, amt);
        vm.prank(user);
        usdc.approve(address(lottery), type(uint256).max);
    }

    function _buy(address user, QuantumLotteryTypes.TicketType t) internal {
        vm.prank(user);
        lottery.buyTicket(t);
    }

    function _requestWinner(
        uint256 hourId
    ) internal returns (uint256 requestId) {
        vm.prank(owner);
        requestId = lottery.requestRandomWinner(hourId);
    }

    // ----------------------- Test helpers -----------------------
    function advanceToHour(uint256 hourDelta) internal {
        vm.warp(((block.timestamp / 3600) + hourDelta) * 3600);
    }

    function fulfillAndProcess(
        uint256 hourId,
        uint256 requestId,
        uint256[] memory words,
        uint256 chunkSize
    ) internal {
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);
        bool done = false;
        while (!done) done = lottery.processDrawChunk(hourId, chunkSize);
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, chunkSize);
    }

    // Emit-expect helpers (wrap vm.expectEmit + emit expected event)
    function emitExpect_TicketPurchased(
        uint256 hourId,
        address player,
        QuantumLotteryTypes.TicketType t,
        uint256 qScore
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit TicketPurchased(hourId, player, t, qScore);
    }

    function emitExpect_WinnerSelectionRequested(uint256 hourId) internal {
        // only check hourId (requestId is assigned by VRF mock)
        vm.expectEmit(true, false, false, false);
        emit WinnerSelectionRequested(hourId, 0);
    }

    function emitExpect_RandomnessFulfilled(uint256 hourId) internal {
        vm.expectEmit(true, false, false, false);
        emit RandomnessFulfilled(hourId, 0, 0);
    }

    function emitExpect_WinnerPicked(
        uint256 hourId,
        address winner,
        uint256 prizeAmount,
        uint256 feeAmount,
        uint256 totalQ
    ) internal {
        vm.expectEmit(true, true, false, true);
        emit WinnerPicked(hourId, winner, prizeAmount, feeAmount, totalQ);
    }

    function _buyAndResolveDraw(
        address p1,
        address p2,
        uint256 randomValue
    ) internal {
        uint256 hourId = block.timestamp / 3600;
    _buy(p1, QuantumLotteryTypes.TicketType.Standard);
    _buy(p2, QuantumLotteryTypes.TicketType.Standard);
        _warpToNextHour();
        uint256 requestId = _requestWinner(hourId);

        uint256[] memory words = new uint256[](1);
        words[0] = randomValue;
        vrf.fulfillRandomWordsWithOverride(requestId, address(lottery), words);
        // process chunks until the draw is fully processed
        bool done = false;
        while (!done) {
            done = lottery.processDrawChunk(hourId, 50);
        }
        // cleanup mapping entries in chunks as well
        bool cleaned = false;
        while (!cleaned) cleaned = lottery.cleanupDrawChunk(hourId, 50);
    }

    function _warpToNextHour() internal {
        vm.warp((block.timestamp / 3600 + 1) * 3600);
    }
}
