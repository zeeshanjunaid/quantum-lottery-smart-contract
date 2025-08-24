// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryEntry {
    function recordTicketPurchase(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(address => uint256) storage lastEnteredHourPlusOne,
        mapping(uint256 => mapping(address => uint256)) storage participantIndexByHour,
        uint256 hourId,
        address player,
        uint256 qScoreOnEntry,
        QuantumLotteryTypes.TicketType ticketType,
        uint256 ticketPrice
    ) internal {
        QuantumLotteryTypes.Draw storage draw = draws[hourId];
        lastEnteredHourPlusOne[player] = hourId + 1;
        draw.participants.push(
            QuantumLotteryTypes.Participant({
                playerAddress: player,
                qScoreOnEntry: qScoreOnEntry,
                ticketTypeOnEntry: ticketType
            })
        );
        participantIndexByHour[hourId][player] = draw.participants.length;
        draw.prizePot += ticketPrice;
        draw.reservedRefunds += ticketPrice;
    }
}
