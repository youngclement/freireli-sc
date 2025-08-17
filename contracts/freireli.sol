// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LogisticsBase.sol";

contract Logistics is LogisticsBase {
    /// @notice Tạo shipment mới (kèm ký quỹ tùy chọn bằng msg.value)
    function createShipment(
        string calldata code,
        string calldata productName,
        string calldata origin,
        string calldata destination,
        address carrier
    ) external payable {
        require(bytes(code).length > 0, "Empty code");
        require(shipments[code].creator == address(0), "Shipment exists");
        require(carrier != address(0), "Carrier zero");

        // Tránh literal struct lớn => gán từng trường
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
        // các cờ boolean mặc định false; rating mặc định 0

        // Audit “khởi tạo”
        _statusHistory[code].push(StatusChange({
            oldStatus: StatusEnum.Pending,
            newStatus: StatusEnum.Pending,
            timestamp: block.timestamp,
            changedBy: msg.sender,
            note: "Shipment created"
        }));

        emit ShipmentCreated(code, msg.value);
    }

    /// @notice Thêm event vận chuyển
    function addShipmentEvent(
        string calldata code,
        string calldata location,
        string calldata eventType
    ) external {
        require(shipments[code].creator != address(0), "Not found");

        shipmentEvents[code].push(ShipmentEvent({
            location: location,
            eventType: eventType,
            timestamp: block.timestamp,
            updatedBy: msg.sender
        }));

        emit ShipmentEventAdded(code, eventType);
    }

    /// @notice Cập nhật trạng thái; tự xử lý escrow khi Delivered/Canceled
    function updateShipmentStatus(
        string calldata code,
        StatusEnum newStatus,
        string calldata note
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "Not found");
        require(msg.sender == s.creator || msg.sender == s.carrier, "Not authorized");

        StatusEnum oldS = s.currentStatus;
        s.currentStatus = newStatus;

        _recordStatus(code, oldS, newStatus, note);

        if (newStatus == StatusEnum.Delivered) {
            _releaseEscrow(code);
        } else if (newStatus == StatusEnum.Canceled) {
            _refundEscrow(code);
        }
    }

    /// @notice Creator đánh giá carrier sau khi Delivered
    function rateCarrier(
        string calldata code,
        uint8 rating,
        string calldata feedback
    ) external {
        Shipment storage s = shipments[code];
        require(s.creator != address(0), "Not found");
        require(msg.sender == s.creator, "Only creator");
        require(s.currentStatus == StatusEnum.Delivered, "Not delivered");
        require(!s.rated, "Rated");
        require(rating >= 1 && rating <= 5, "Rating 1..5");

        s.rated = true;
        s.rating = rating;
        s.feedback = feedback;

        CarrierStats storage st = carrierStats[s.carrier];
        st.totalRatingPoints += rating;
        st.ratingCount += 1;

        emit CarrierRated(code, s.carrier, rating, feedback);
    }
}
