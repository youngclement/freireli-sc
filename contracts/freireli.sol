// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Logistics {
    enum StatusEnum {
        Pending,
        Confirmed,
        Packed,
        Departed,
        InTransit,
        Delayed,
        AtCheckpoint,
        OutForDelivery,
        Arrived,
        Delivered,
        Returned,
        Canceled
    }

    struct Status {
        uint8 id;
        string name;
        string description;
    }

    mapping(uint8 => Status) public statuses;

    struct BasicDetails {
        string shipmentCode;
        string orderCode;
        string productName;
        string productType;
        uint256 quantity;
        string unit;
        uint256 weightKg;
        uint256 volumeM3;
    }

    struct ShipmentMeta {
        string origin;
        string destination;
        uint256 expectedPickupTime;
        uint256 expectedDeliveryTime;
        address carrier;
        address receiver;
        string insuranceProvider;
        bool isFragile;
        string note;
    }

    struct Shipment {
        string shipmentCode;
        string orderCode;
        string productName;
        string productType;
        uint256 quantity;
        string unit;
        uint256 weightKg;
        uint256 volumeM3;
        string origin;
        string destination;
        uint256 expectedPickupTime;
        uint256 expectedDeliveryTime;
        StatusEnum currentStatus;
        address creator;
        address carrier;
        address receiver;
        string insuranceProvider;
        bool isFragile;
        string note;
    }

    mapping(string => Shipment) public shipments;

    struct ShipmentEvent {
        string id;
        string shipmentCode;
        string location;
        string gpsLatitude;
        string gpsLongitude;
        string eventType;
        string eventDescription;
        uint256 timestamp;
        address updatedBy;
        string signatureHash;
        string imageProofCID;
    }

    mapping(string => ShipmentEvent[]) public shipmentEvents;

    event ShipmentCreated(string shipmentCode);
    event ShipmentEventAdded(string shipmentCode, string eventType);
    event ShipmentStatusUpdated(string shipmentCode, StatusEnum newStatus);

    function createShipment(BasicDetails memory details, ShipmentMeta memory meta) public {
        require(shipments[details.shipmentCode].creator == address(0), "Shipment already exists");

        shipments[details.shipmentCode] = Shipment({
            shipmentCode: details.shipmentCode,
            orderCode: details.orderCode,
            productName: details.productName,
            productType: details.productType,
            quantity: details.quantity,
            unit: details.unit,
            weightKg: details.weightKg,
            volumeM3: details.volumeM3,
            origin: meta.origin,
            destination: meta.destination,
            expectedPickupTime: meta.expectedPickupTime,
            expectedDeliveryTime: meta.expectedDeliveryTime,
            currentStatus: StatusEnum.Pending,
            creator: msg.sender,
            carrier: meta.carrier,
            receiver: meta.receiver,
            insuranceProvider: meta.insuranceProvider,
            isFragile: meta.isFragile,
            note: meta.note
        });

        emit ShipmentCreated(details.shipmentCode);
    }

    function addShipmentEvent(
        string memory _shipmentCode,
        string memory _eventId,
        string memory _location,
        string memory _gpsLat,
        string memory _gpsLong,
        string memory _eventType,
        string memory _eventDescription,
        string memory _signatureHash,
        string memory _imageCID
    ) public {
        require(shipments[_shipmentCode].creator != address(0), "Shipment not found");

        shipmentEvents[_shipmentCode].push(ShipmentEvent({
            id: _eventId,
            shipmentCode: _shipmentCode,
            location: _location,
            gpsLatitude: _gpsLat,
            gpsLongitude: _gpsLong,
            eventType: _eventType,
            eventDescription: _eventDescription,
            timestamp: block.timestamp,
            updatedBy: msg.sender,
            signatureHash: _signatureHash,
            imageProofCID: _imageCID
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

    function addStatus(uint8 _id, string memory _name, string memory _desc) public {
        statuses[_id] = Status({
            id: _id,
            name: _name,
            description: _desc
        });
    }

    function getShipmentEvents(string memory _shipmentCode) public view returns (ShipmentEvent[] memory) {
        return shipmentEvents[_shipmentCode];
    }
}
