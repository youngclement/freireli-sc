// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Logistics {
    enum StatusEnum {
        Pending,
        InTransit,
        Delivered,
        Canceled
    }

    struct Shipment {
        string shipmentCode;
        string productName;
        string origin;
        string destination;
        StatusEnum currentStatus;
        address creator;
        address carrier;
        uint256 createdAt;
    }

    struct ShipmentEvent {
        string location;
        string eventType;
        uint256 timestamp;
        address updatedBy;
    }

    mapping(string => Shipment) public shipments;
    mapping(string => ShipmentEvent[]) public shipmentEvents;

    event ShipmentCreated(string shipmentCode);
    event ShipmentEventAdded(string shipmentCode, string eventType);
    event ShipmentStatusUpdated(string shipmentCode, StatusEnum newStatus);

    function createShipment(
        string memory _shipmentCode,
        string memory _productName,
        string memory _origin,
        string memory _destination,
        address _carrier
    ) public {
        require(bytes(_shipmentCode).length > 0, "Shipment code cannot be empty");
        require(shipments[_shipmentCode].creator == address(0), "Shipment already exists");

        shipments[_shipmentCode] = Shipment({
            shipmentCode: _shipmentCode,
            productName: _productName,
            origin: _origin,
            destination: _destination,
            currentStatus: StatusEnum.Pending,
            creator: msg.sender,
            carrier: _carrier,
            createdAt: block.timestamp
        });

        emit ShipmentCreated(_shipmentCode);
    }

    function addShipmentEvent(
        string memory _shipmentCode,
        string memory _location,
        string memory _eventType
    ) public {
        require(shipments[_shipmentCode].creator != address(0), "Shipment not found");

        shipmentEvents[_shipmentCode].push(ShipmentEvent({
            location: _location,
            eventType: _eventType,
            timestamp: block.timestamp,
            updatedBy: msg.sender
        }));

        emit ShipmentEventAdded(_shipmentCode, _eventType);
    }

    function updateShipmentStatus(string memory _shipmentCode, StatusEnum _newStatus) public {
        require(shipments[_shipmentCode].creator != address(0), "Shipment not found");
        require(
            msg.sender == shipments[_shipmentCode].creator ||
            msg.sender == shipments[_shipmentCode].carrier,
            "Not authorized"
        );

        shipments[_shipmentCode].currentStatus = _newStatus;
        emit ShipmentStatusUpdated(_shipmentCode, _newStatus);
    }

    function getShipment(string memory _shipmentCode) public view returns (Shipment memory) {
        return shipments[_shipmentCode];
    }

    function getShipmentEvents(string memory _shipmentCode) public view returns (ShipmentEvent[] memory) {
        return shipmentEvents[_shipmentCode];
    }
}
