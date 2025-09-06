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
        address warehouseManager;
        address qualityInspector;
        uint256 createdAt;
        uint256 depositAmount;
        uint256 shippingFee;
        uint8 flags; // bit flags: escrowReleased(0), escrowRefunded(1), warehouseConfirmed(2), qualityApproved(3), receiverConfirmed(4), rated(5), disputed(6)
        uint8 rating;
        string feedback;
        string disputeReason;
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
    mapping(address => bool) public authorizedInspectors;
    mapping(address => bool) public authorizedWarehouseManagers;
    address public admin;

    // ===== Events =====
    event ShipmentCreated(string shipmentCode, uint256 depositAmount);
    event ShipmentEventAdded(string shipmentCode, string eventType);
    event ShipmentStatusUpdated(string shipmentCode, StatusEnum oldStatus, StatusEnum newStatus, string note);
    event EscrowReleased(string shipmentCode, address carrier, uint256 amount);
    event EscrowRefunded(string shipmentCode, address creator, uint256 amount);
    event CarrierRated(string shipmentCode, address carrier, uint8 rating, string feedback);
    event ConfirmationUpdated(string shipmentCode, address actor, uint8 confirmationType);
    event DisputeRaised(string shipmentCode, string reason, address raisedBy);

    // ===== Modifiers =====
    modifier onlyAdmin() {
        require(msg.sender == admin, "!admin");
        _;
    }

    // ===== Constructor =====
    constructor() {
        admin = msg.sender;
    }

    // ===== Admin functions =====
    function setAuthorized(address user, bool authorized, bool isInspector) external onlyAdmin {
        if (isInspector) {
            authorizedInspectors[user] = authorized;
        } else {
            authorizedWarehouseManagers[user] = authorized;
        }
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "!addr");
        admin = newAdmin;
    }

    // ===== Helper functions =====
    function _getFlag(string memory code, uint8 flagIndex) internal view returns (bool) {
        return (shipments[code].flags >> flagIndex) & 1 == 1;
    }

    function _setFlag(string memory code, uint8 flagIndex, bool value) internal {
        if (value) {
            shipments[code].flags |= (1 << flagIndex);
        } else {
            shipments[code].flags &= ~(1 << flagIndex);
        }
    }

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
        if (_getFlag(code, 0) || _getFlag(code, 1) || amount == 0) return;
        _setFlag(code, 0, true);
        (bool ok, ) = s.carrier.call{value: amount}("");
        require(ok, "!transfer");
        emit EscrowReleased(code, s.carrier, amount);
    }

    function _refundEscrow(string memory code) internal nonReentrant {
        Shipment storage s = shipments[code];
        uint256 amount = s.depositAmount;
        if (_getFlag(code, 0) || _getFlag(code, 1) || amount == 0) return;
        _setFlag(code, 1, true);
        (bool ok, ) = s.creator.call{value: amount}("");
        require(ok, "!refund");
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
