// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LogisticsBase.sol";

contract Logistics is LogisticsBase {
    /// @notice Tạo shipment
    function createShipment(
        string calldata code,
        string calldata productName,
        string calldata origin,
        string calldata destination,
        address carrier,
        uint256 shippingFee
    ) external payable {
        require(bytes(code).length > 0, "!code");
        require(shipments[code].creator == address(0), "exists");
        require(carrier != address(0), "!carrier");
        require(msg.value >= shippingFee, "!deposit");

        Shipment storage s = shipments[code];
        s.shipmentCode = code;
        s.productName = productName;
        s.origin = origin;
        s.destination = destination;
        s.currentStatus = StatusEnum.Pending;
        s.creator = msg.sender;
        s.carrier = carrier;
        s.createdAt = block.timestamp;
        s.depositAmount = msg.value;
        s.shippingFee = shippingFee;

        emit ShipmentCreated(code, msg.value);
    }

    /// @notice Set actors
    function setActors(string calldata code, address manager, address inspector) external onlyAdmin {
        require(shipments[code].creator != address(0), "!found");
        require(authorizedWarehouseManagers[manager], "!manager");
        require(authorizedInspectors[inspector], "!inspector");
        shipments[code].warehouseManager = manager;
        shipments[code].qualityInspector = inspector;
    }

    /// @notice Confirm warehouse/quality
    function confirm(string calldata code, bool isWarehouse) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");
        require(s.currentStatus == StatusEnum.Pending, "!pending");

        if (isWarehouse) {
            require(msg.sender == s.warehouseManager, "!manager");
            require(!_getFlag(code, 2), "confirmed");
            _setFlag(code, 2, true);
            emit ConfirmationUpdated(code, msg.sender, 1);
        } else {
            require(msg.sender == s.qualityInspector, "!inspector");
            require(_getFlag(code, 2), "!warehouse");
            require(!_getFlag(code, 3), "approved");
            _setFlag(code, 3, true);
            emit ConfirmationUpdated(code, msg.sender, 2);
        }
    }

    /// @notice Start transit
    function startTransit(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");
        require(msg.sender == s.carrier, "!carrier");
        require(_getFlag(code, 2) && _getFlag(code, 3), "!ready");
        require(s.currentStatus == StatusEnum.Pending, "!pending");
        s.currentStatus = StatusEnum.InTransit;
    }

    /// @notice Confirm delivery
    function confirmDelivery(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");
        require(msg.sender == s.creator, "!receiver");
        require(s.currentStatus == StatusEnum.InTransit, "!transit");
        
        _setFlag(code, 4, true);
        s.currentStatus = StatusEnum.Delivered;
        emit ConfirmationUpdated(code, msg.sender, 3);
        _releaseEscrow(code);
    }

    /// @notice Update shipment
    function updateShipment(
        string calldata code,
        string calldata location,
        StatusEnum newStatus
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");
        require(msg.sender == s.carrier || msg.sender == admin, "!auth");

        if (bytes(location).length > 0) {
            shipmentEvents[code].push(ShipmentEvent({
                location: location,
                eventType: "update",
                timestamp: block.timestamp,
                updatedBy: msg.sender
            }));
            emit ShipmentEventAdded(code, "update");
        }

        if (newStatus != s.currentStatus) {
            s.currentStatus = newStatus;
            if (newStatus == StatusEnum.Delivered) {
                _setFlag(code, 4, true);
                emit ConfirmationUpdated(code, msg.sender, 3);
                _releaseEscrow(code);
            } else if (newStatus == StatusEnum.Canceled) {
                _refundEscrow(code);
            }
        }
    }

    /// @notice Rate or dispute
    function rateOrDispute(
        string calldata code,
        uint8 rating,
        string calldata feedback,
        bool isDispute
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");

        if (isDispute) {
            require(msg.sender == s.creator || msg.sender == s.carrier, "!auth");
            require(!_getFlag(code, 6), "disputed");
            require(s.currentStatus != StatusEnum.Delivered, "!dispute");
            _setFlag(code, 6, true);
            s.disputeReason = feedback;
            emit DisputeRaised(code, feedback, msg.sender);
        } else {
            require(msg.sender == s.creator, "!creator");
            require(s.currentStatus == StatusEnum.Delivered, "!delivered");
            require(!_getFlag(code, 5), "rated");
            require(rating >= 1 && rating <= 5, "!rating");

            _setFlag(code, 5, true);
            s.rating = rating;
            s.feedback = feedback;
            carrierStats[s.carrier].totalRatingPoints += rating;
            carrierStats[s.carrier].ratingCount += 1;
            emit CarrierRated(code, s.carrier, rating, feedback);
        }
    }

    /// @notice Resolve dispute
    function resolveDispute(string calldata code, bool favorCreator) external onlyAdmin {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "!found");
        require(_getFlag(code, 6), "!disputed");

        _setFlag(code, 6, false);
        if (favorCreator) {
            s.currentStatus = StatusEnum.Canceled;
            _refundEscrow(code);
        } else {
            s.currentStatus = StatusEnum.Delivered;
            _releaseEscrow(code);
        }
    }
}
