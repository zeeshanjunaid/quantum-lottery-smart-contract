// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryEntry {
    function recordTicketPurchase(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(address => uint256) storage lastEnteredHourPlusOne,
        mapping(uint256 => mapping(address => uint256))
            storage s_participantIndexByHour,
        uint256 _hourId,
        address _player,
        uint256 _qScoreOnEntry,
        QuantumLotteryTypes.TicketType _ticketType,
        uint256 _ticketPrice
    ) internal {
        QuantumLotteryTypes.Draw storage draw = draws[_hourId];
        lastEnteredHourPlusOne[_player] = _hourId + 1;
        draw.participants.push(
            QuantumLotteryTypes.Participant({
                playerAddress: _player,
                qScoreOnEntry: _qScoreOnEntry,
                ticketTypeOnEntry: _ticketType
            })
        );
        s_participantIndexByHour[_hourId][_player] = draw.participants.length;
        draw.prizePot += _ticketPrice;
        draw.reservedRefunds += _ticketPrice;
    }
}
