// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract LogisticsBase {
    // ===== Enums =====
    enum StatusEnum { Pending, InTransit, Delivered, Canceled }

    // ===== Data structs =====
    struct Shipment {
        string shipmentCode;
        string productName;
        string origin;
        string destination;
        StatusEnum currentStatus;
        address creator;
        address carrier;
        uint256 createdAt;
        // Escrow
        uint256 depositAmount;
        bool escrowReleased;
        bool escrowRefunded;
        // Rating
        bool rated;
        uint8 rating;      // 1..5
        string feedback;
    }

    struct ShipmentEvent {
        string location;
        string eventType;
        uint256 timestamp;
        address updatedBy;
    }

    struct StatusChange {
        StatusEnum oldStatus;
        StatusEnum newStatus;
        uint256 timestamp;
        address changedBy;
        string note;
    }

    struct CarrierStats {
        uint256 totalRatingPoints;
        uint256 ratingCount;
    }

    // ===== Storage =====
    mapping(string => Shipment) internal shipments;
    mapping(string => ShipmentEvent[]) internal shipmentEvents;
    mapping(string => StatusChange[]) internal _statusHistory;
    mapping(address => CarrierStats) public carrierStats;

    // ===== Events =====
    event ShipmentCreated(string shipmentCode, uint256 depositAmount);
    event ShipmentEventAdded(string shipmentCode, string eventType);
    event ShipmentStatusUpdated(string shipmentCode, StatusEnum oldStatus, StatusEnum newStatus, string note);
    event EscrowReleased(string shipmentCode, address carrier, uint256 amount);
    event EscrowRefunded(string shipmentCode, address creator, uint256 amount);
    event CarrierRated(string shipmentCode, address carrier, uint8 rating, string feedback);

    // ===== Reentrancy guard (nhẹ) =====
    bool private _locked;
    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard");
        _locked = true;
        _;
        _locked = false;
    }

    // ===== Internal helpers =====
    function _recordStatus(
        string memory code,
        StatusEnum oldS,
        StatusEnum newS,
        string memory note
    ) internal {
        _statusHistory[code].push(StatusChange({
            oldStatus: oldS,
            newStatus: newS,
            timestamp: block.timestamp,
            changedBy: msg.sender,
            note: note
        }));
        emit ShipmentStatusUpdated(code, oldS, newS, note);
    }

    function _releaseEscrow(string memory code) internal nonReentrant {
        Shipment storage s = shipments[code];
        uint256 amount = s.depositAmount;
        if (s.escrowReleased || s.escrowRefunded || amount == 0) return;
        s.escrowReleased = true;
        (bool ok, ) = s.carrier.call{value: amount}("");
        require(ok, "Transfer to carrier failed");
        emit EscrowReleased(code, s.carrier, amount);
    }

    function _refundEscrow(string memory code) internal nonReentrant {
        Shipment storage s = shipments[code];
        uint256 amount = s.depositAmount;
        if (s.escrowReleased || s.escrowRefunded || amount == 0) return;
        s.escrowRefunded = true;
        (bool ok, ) = s.creator.call{value: amount}("");
        require(ok, "Refund to creator failed");
        emit EscrowRefunded(code, s.creator, amount);
    }

    // ===== Views (shared) =====
    function getShipment(string memory code) public view returns (Shipment memory) {
        return shipments[code];
    }

    function getShipmentEvents(string memory code) public view returns (ShipmentEvent[] memory) {
        return shipmentEvents[code];
    }

    function getStatusHistory(string memory code) public view returns (StatusChange[] memory) {
        return _statusHistory[code];
    }

    function getCarrierAverageRating(address carrier) external view returns (uint256 avgTimes100) {
        CarrierStats memory st = carrierStats[carrier];
        if (st.ratingCount == 0) return 0;
        return (st.totalRatingPoints * 100) / st.ratingCount; // ví dụ 423 = 4.23
    }
}
