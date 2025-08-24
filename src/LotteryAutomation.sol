// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AutomationCompatibleInterface} from "chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {ConfirmedOwner} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {QuantumLottery} from "./QuantumLottery.sol";
import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

/// @title LotteryAutomation
/// @notice Chainlink Automation keeper to fully automate draw lifecycle
/// @dev Own this contract and transfer the QuantumLottery ownership to it for zero manual ops
contract LotteryAutomation is AutomationCompatibleInterface, ConfirmedOwner {

    enum Action {
        NONE,
        REQUEST_WINNER,
        PROCESS_CHUNK,
        CLEANUP_CHUNK,
        FORCE_RESOLVE
    }

    QuantumLottery public immutable lottery;
    uint256 public iterations; // how many items per process/cleanup step
    uint256 public minParticipants; // require at least this many to request resolve
    bool public enableForceResolve = true;

    event IterationsUpdated(uint256 iterations);
    event MinParticipantsUpdated(uint256 minParticipants);
    event ForceResolveToggled(bool enabled);

    constructor(address _lottery, uint256 _iterations) ConfirmedOwner(msg.sender) {
        require(_lottery != address(0), "lottery=0");
        require(_iterations != 0, "iterations=0");
        lottery = QuantumLottery(_lottery);
        iterations = _iterations;
        minParticipants = 1;
    }

    // Admin
    function setIterations(uint256 _iterations) external onlyOwner {
        require(_iterations != 0, "iterations=0");
        iterations = _iterations;
        emit IterationsUpdated(_iterations);
    }

    function setMinParticipants(uint256 _min) external onlyOwner {
        minParticipants = _min;
        emit MinParticipantsUpdated(_min);
    }

    function setForceResolve(bool _enabled) external onlyOwner {
        enableForceResolve = _enabled;
        emit ForceResolveToggled(_enabled);
    }

    /// @notice Called by owner to complete two-step ownership transfer on the Lottery
    function acceptLotteryOwnership() external onlyOwner {
        lottery.acceptOwnership();
    }

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 nowTs = block.timestamp;
        uint256 currHour = nowTs / lottery.SECONDS_PER_HOUR();
        if (currHour == 0) return (false, bytes(""));
        uint256 targetHour = currHour - 1;

        QuantumLotteryTypes.DrawStatus status = lottery.getDrawStatus(targetHour);

        if (status == QuantumLotteryTypes.DrawStatus.OPEN) {
            uint256 participants = lottery.getParticipantsCount(targetHour);
            if (participants >= minParticipants) {
                return (true, abi.encode(Action.REQUEST_WINNER, targetHour));
            }
        } else if (status == QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER) {
            if (enableForceResolve) {
                uint256 reqTs = lottery.getRequestTimestamp(targetHour);
                if (reqTs != 0 && nowTs >= reqTs + lottery.DRAW_RESOLUTION_TIMEOUT()) {
                    return (true, abi.encode(Action.FORCE_RESOLVE, targetHour));
                }
            }
        } else if (status == QuantumLotteryTypes.DrawStatus.RESOLVING) {
            return (true, abi.encode(Action.PROCESS_CHUNK, targetHour));
        } else if (status == QuantumLotteryTypes.DrawStatus.RESOLVED) {
            if (lottery.isCleanupPending(targetHour)) {
                return (true, abi.encode(Action.CLEANUP_CHUNK, targetHour));
            }
        }

        return (false, bytes(""));
    }

    /// @inheritdoc AutomationCompatibleInterface
    function performUpkeep(bytes calldata performData) external override {
        (Action action, uint256 hourId) = abi.decode(performData, (Action, uint256));

        if (action == Action.REQUEST_WINNER) {
            lottery.requestRandomWinner(hourId);
        } else if (action == Action.PROCESS_CHUNK) {
            // best-effort single chunk; Automation will call again until done
            lottery.processDrawChunk(hourId, iterations);
        } else if (action == Action.CLEANUP_CHUNK) {
            lottery.cleanupDrawChunk(hourId, iterations);
        } else if (action == Action.FORCE_RESOLVE) {
            lottery.forceResolveDraw(hourId);
        }
        // else: no-op
    }
}
