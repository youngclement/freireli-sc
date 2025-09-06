// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LogisticBase.sol";

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
        require(bytes(code).length > 0);
        require(shipments[code].creator == address(0));
        require(carrier != address(0));
        require(msg.value >= shippingFee);

        Shipment storage s = shipments[code];
        s.shipmentCode   = code;
        s.productName    = productName;
        s.origin         = origin;
        s.destination    = destination;
        s.currentStatus  = StatusEnum.Pending;
        s.creator        = msg.sender;
        s.carrier        = carrier;
        s.createdAt      = block.timestamp;
        s.depositAmount  = msg.value;
        s.shippingFee    = shippingFee;

        emit ShipmentCreated(code, msg.value);
    }

    /// @notice Set actors - Creator hoặc Admin có thể set
    function setActors(string calldata code, address manager, address inspector) external {
        require(shipments[code].creator != address(0));
        require(msg.sender == shipments[code].creator || msg.sender == admin);
        require(authorizedWarehouseManagers[manager]);
        require(authorizedInspectors[inspector]);

        shipments[code].warehouseManager = manager;
        shipments[code].qualityInspector = inspector;
    }

    /// @notice Set warehouse manager riêng
    function setWarehouseManager(string calldata code, address manager) external {
        require(shipments[code].creator != address(0));
        require(msg.sender == shipments[code].creator || msg.sender == admin);
        require(authorizedWarehouseManagers[manager]);
        shipments[code].warehouseManager = manager;
    }

    /// @notice Set quality inspector riêng
    function setQualityInspector(string calldata code, address inspector) external {
        require(shipments[code].creator != address(0));
        require(msg.sender == shipments[code].creator || msg.sender == admin);
        require(authorizedInspectors[inspector]);
        shipments[code].qualityInspector = inspector;
    }

    /// @notice Warehouse confirm
    function warehouseConfirm(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.warehouseManager);
        require(s.currentStatus == StatusEnum.Pending);
        require(!_getFlag(code, 2));

        _setFlag(code, 2, true);
        s.currentStatus = StatusEnum.WarehouseConfirmed;

        _addEvent(code, "Warehouse", "warehouse_confirmed");
        emit ConfirmationUpdated(code, msg.sender, 1);
    }

    /// @notice Quality approve
    function qualityApprove(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.qualityInspector);
        require(s.currentStatus == StatusEnum.WarehouseConfirmed);
        require(_getFlag(code, 2));
        require(!_getFlag(code, 3));

        _setFlag(code, 3, true);
        s.currentStatus = StatusEnum.QualityApproved;

        _addEvent(code, "Quality Control", "quality_approved");
        emit ConfirmationUpdated(code, msg.sender, 2);
    }

    /// @notice Cancel shipment - Chỉ admin có thể cancel
    function cancelShipment(string calldata code, string calldata reason) external onlyAdmin {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(s.currentStatus != StatusEnum.Delivered);
        require(s.currentStatus != StatusEnum.Canceled);
        require(bytes(reason).length > 0);

        s.currentStatus = StatusEnum.Canceled;
        _addEvent(code, "System", "canceled");
        _refundEscrow(code);
    }

    /// @notice Add event - internal helper
    function _addEvent(
        string calldata code,
        string memory location,
        string memory eventType
    ) internal {
        shipmentEvents[code].push(ShipmentEvent({
            location: location,
            eventType: eventType,
            timestamp: block.timestamp,
            updatedBy: msg.sender
        }));
        emit ShipmentEventAdded(code, eventType);
    }

    /// @notice Warehouse Manager & Quality Inspector có thể thêm event
    function addShipmentEvent(
        string calldata code,
        string calldata location,
        string calldata eventType
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(
            msg.sender == s.warehouseManager ||
            msg.sender == s.qualityInspector
        );
        require(bytes(location).length > 0);
        require(bytes(eventType).length > 0);

        _addEvent(code, location, eventType);
    }

    /// @notice Carrier thêm transit events (chỉ khi đang InTransit)
    function addTransitEvent(
        string calldata code,
        string calldata location,
        string calldata note
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.carrier);
        require(s.currentStatus == StatusEnum.InTransit);
        require(bytes(location).length > 0);

        _addEvent(code, location, note);
    }

    /// @notice Warehouse Manager thêm warehouse-specific events
    function addWarehouseEvent(
        string calldata code,
        string calldata eventType
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.warehouseManager);
        require(bytes(eventType).length > 0);

        _addEvent(code, "Warehouse", eventType);
    }

    /// @notice Quality Inspector thêm quality-specific events
    function addQualityEvent(
        string calldata code,
        string calldata eventType
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.qualityInspector);
        require(bytes(eventType).length > 0);

        _addEvent(code, "Quality Control", eventType);
    }

    /// @notice Bắt đầu vận chuyển: cần đủ xác nhận
    function startTransit(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.carrier);
        require(_getFlag(code, 2) && _getFlag(code, 3));
        require(s.currentStatus == StatusEnum.QualityApproved);

        s.currentStatus = StatusEnum.InTransit;
        _addEvent(code, s.origin, "transit_started");
    }

    /// @notice Xác nhận giao hàng (receiver = creator)
    function confirmDelivery(string calldata code) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(msg.sender == s.creator);
        require(s.currentStatus == StatusEnum.InTransit);

        _setFlag(code, 4, true);
        s.currentStatus = StatusEnum.Delivered;

        _addEvent(code, s.destination, "delivery_confirmed");
        emit ConfirmationUpdated(code, msg.sender, 3);
        _releaseEscrow(code);
    }

    /// @notice Cập nhật vị trí (không đổi status)
    function updateLocation(
        string calldata code,
        string calldata location,
        string calldata eventType
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(
            msg.sender == s.carrier ||
            msg.sender == admin ||
            msg.sender == s.warehouseManager ||
            msg.sender == s.qualityInspector
        );
        require(bytes(location).length > 0);
        require(bytes(eventType).length > 0);

        _addEvent(code, location, eventType);
    }

    /// @notice Đánh giá hoặc khiếu nại
    function rateOrDispute(
        string calldata code,
        uint8 rating,
        string calldata feedback,
        bool isDispute
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));

        if (isDispute) {
            require(msg.sender == s.creator || msg.sender == s.carrier);
            require(!_getFlag(code, 6));
            require(s.currentStatus != StatusEnum.Delivered);

            _setFlag(code, 6, true);
            s.disputeReason = feedback;
            emit DisputeRaised(code, feedback, msg.sender);
        } else {
            require(msg.sender == s.creator);
            require(s.currentStatus == StatusEnum.Delivered);
            require(!_getFlag(code, 5));
            require(rating >= 1 && rating <= 5);

            _setFlag(code, 5, true);
            s.rating  = rating;
            s.feedback = feedback;

            carrierStats[s.carrier].totalRatingPoints += rating;
            carrierStats[s.carrier].ratingCount += 1;

            emit CarrierRated(code, s.carrier, rating, feedback);
        }
    }

    /// @notice Giải quyết khiếu nại
    function resolveDispute(
        string calldata code,
        bool favorCreator
    ) external onlyAdmin {
        Shipment storage s = shipments[code];
        require(s.creator != address(0));
        require(_getFlag(code, 6));

        _setFlag(code, 6, false);

        if (favorCreator) {
            s.currentStatus = StatusEnum.Canceled;
            _addEvent(code, "System", "dispute_resolved_creator");
            _refundEscrow(code);
        } else {
            s.currentStatus = StatusEnum.Delivered;
            _addEvent(code, "System", "dispute_resolved_carrier");
            _releaseEscrow(code);
        }
    }

    /// @notice Tracking đầy đủ
    function getFullTrackingInfo(string calldata code)
        external
        view
        returns (
            Shipment memory shipment,
            ShipmentEvent[] memory events,
            StatusChange[] memory statusHistory,
            uint8 status
        )
    {
        shipment = getShipment(code);
        events = getShipmentEvents(code);
        statusHistory = getStatusHistory(code);
        status = uint8(shipment.currentStatus);
    }
}
