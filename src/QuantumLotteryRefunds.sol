// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryRefunds {
    error NoRefundAvailable();

    function claimRefundCore(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(uint256 => mapping(address => uint256))
            storage participantIndexByHour,
        mapping(uint256 => mapping(address => bool))
            storage refundClaimedByHour,
        uint256 hourId,
        address claimer,
        uint256 STANDARD_TICKET_PRICE,
        uint256 QUANTUM_TICKET_PRICE
    ) internal returns (uint256 refundAmount) {
        QuantumLotteryTypes.Draw storage draw = draws[hourId];

        uint256 idx = participantIndexByHour[hourId][claimer];
        if (idx == 0) revert NoRefundAvailable();
        if (refundClaimedByHour[hourId][claimer]) {
            revert NoRefundAvailable();
        }

        QuantumLotteryTypes.Participant storage p = draw.participants[idx - 1];
        if (p.playerAddress == address(0)) revert NoRefundAvailable();

        refundAmount = p.ticketTypeOnEntry == QuantumLotteryTypes.TicketType.Standard
            ? STANDARD_TICKET_PRICE
            : QUANTUM_TICKET_PRICE;

        // mark claimed and clear participant slot and index
    refundClaimedByHour[hourId][claimer] = true;
        p.playerAddress = address(0);
    participantIndexByHour[hourId][claimer] = 0;

        // decrement reserved refunds liability
        draw.reservedRefunds -= refundAmount;
        return refundAmount;
    }
}
