// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title QuantumLotteryTypes
 * @notice Contains enums, structs, errors, and events for QuantumLottery contracts.
 */
contract QuantumLotteryTypes {
    // ========================= CONSTANTS =========================
    uint256 public constant MAX_PARTICIPANTS = 500;
    uint256 public constant MAX_QSCORE = 100000;
    uint256 public constant DRAW_RESOLUTION_TIMEOUT = 12 hours;
    uint256 public constant UNCLAIMED_REFUND_PERIOD = 365 days;
    uint32 public constant CALLBACK_GAS_LIMIT = 2500000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;
    uint256 public constant BASELINE_QSCORE = 100;
    uint256 public constant BASE_LOSS_BONUS = 10;
    uint256 public constant STREAK_BONUS = 15;
    uint256 public constant BLAZING_STREAK_BONUS = 20;
    uint256 public constant QUANTUM_TICKET_BONUS = 40;
    uint32 public constant STREAK_MODE_THRESHOLD = 5;
    uint32 public constant BLAZING_STREAK_THRESHOLD = 10;
    uint256 public constant COSMIC_SURGE_MULTIPLIER = 3;
    // Prices are in 6-decimal USDC units
    uint256 public constant STANDARD_TICKET_PRICE = 10_000_000; // 10 USDC
    uint256 public constant QUANTUM_TICKET_PRICE = 30_000_000; // 30 USDC
    uint256 public constant WINNER_PAYOUT_PERCENT = 92;
    uint256 public constant PERCENTAGE_TOTAL = 100;
    uint256 public constant SECONDS_PER_HOUR = 3600;
    uint256 public constant MAX_CAPPED_PLAYERS_TEMP = 1000; // Max array size for temp storage

    // ========================= ENUMS =========================
    enum TicketType {
        Standard,
        Quantum
    }

    enum DrawStatus {
        OPEN,
        CALCULATING_WINNER,
        RESOLVING,
        RESOLVED
    }

    // ========================= ERRORS =========================
    error DrawNotOpen();
    error PlayerAlreadyEntered();
    error DrawHasNoParticipants();
    error DrawAlreadyResolvedOrCalculating();
    error InvalidRequestIdForLottery();
    error DrawCannotBeClosedYet();
    error DrawIsFull();
    error VrfRequestFailed();
    error NoRefundAvailable();
    error IndexOutOfBounds();
    error DrawNotStuck();
    error TimeoutNotReached();
    error InvalidTicketType();
    error InvalidCallerAddress();
    error TooManyParticipants();
    error QScoreTotalOverflow();

    // ========================= STRUCTS =========================
    struct Player {
        uint64 lastPlayedHour;
        uint32 streakCount;
        uint256 qScore;
    }

    struct Participant {
        address playerAddress;
        uint256 qScoreOnEntry;
        TicketType ticketTypeOnEntry;
    }

    struct Draw {
        uint256 prizePot;
        uint256 reservedRefunds;
        uint256 totalQScoreInPool;
        Participant[] participants;
        address winner;
        DrawStatus status;
        uint256 requestTimestamp;
        bool forceResolved;
        uint256 processingIndex;
        uint256 cumulativeScore;
        uint256 randomValue;
        bool winnerPicked;
        uint256 winnerIndex;
        bool processingWrapped;
        uint256 cleanupIndex;
        bool cleanupPending;
        bool cosmicActive;
    }

    // ========================= EVENTS =========================
    event TicketPurchased(uint256 indexed hourId, address indexed player, TicketType ticketType, uint256 qScoreOnEntry);
    event WinnerSelectionRequested(uint256 indexed hourId, uint256 indexed requestId);
    event RandomnessFulfilled(uint256 indexed hourId, uint256 indexed requestId, uint256 totalQScoreInPool);
    event WinnerPicked(
        uint256 indexed hourId,
        address indexed winner,
        uint256 prizeAmount,
        uint256 feeAmount,
        uint256 totalQScoreInPool
    );
    event CosmicSurgeScheduled(uint256 indexed hourId);
    event CosmicSurgeCanceled(uint256 indexed hourId);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event DrawForceResolved(uint256 indexed hourId);
    event DrawForceResolvedWithCount(uint256 indexed hourId, uint256 participantCount);
    event RefundIssued(uint256 indexed hourId, address indexed player, uint256 amount, uint256 remainingLiability);
    event WithdrawUnclaimed(uint256 indexed hourId, address indexed to, uint256 amount, uint256 remainingLiability);
    event QScoreCapped(address indexed player, uint256 indexed hourId, uint256 cappedAt);
}
