// hrms/lib/models/customer.dart
import 'package:json_annotation/json_annotation.dart';

part 'customer.g.dart';

@JsonSerializable(includeIfNull: false)
class Customer {
  @JsonKey(name: '_id')
  final String? id;
  final String customerName;
  final String? customerNumber;
  final String? companyName;
  final String? email;
  @JsonKey(name: 'emailId')
  final String? emailId; // Used in customers collection
  final String address;

  /// Email for OTP - uses emailId when email is null (customers collection uses emailId).
  String? get effectiveEmail => email ?? emailId;
  final String city;
  final String pincode;

  /// Dial code without +, e.g. "91" for India.
  final String? countryCode;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  final String? state;
  final double? latitude;
  final double? longitude;
  final double? radius;

  Customer({
    this.id,
    required this.customerName,
    this.customerNumber,
    this.companyName,
    this.email,
    this.emailId,
    required this.address,
    required this.city,
    required this.pincode,
    this.countryCode,
    this.state,
    this.latitude,
    this.longitude,
    this.radius,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    final name = (json['customerName'] ?? json['name'] ?? '').toString();
    final number = (json['customerNumber'] ?? json['mobile'])?.toString();
    final company = (json['companyName'] ?? json['company'])?.toString();
    final mail = (json['email'] ?? json['emailId'])?.toString();
    final addr = (json['address'] ?? '').toString();
    final c = (json['city'] ?? '').toString();
    final pin = (json['pincode'] ?? json['pinCode'] ?? '').toString();
    final cCode = (json['countryCode'] ?? '91').toString();
    final idVal = (json['_id'] ?? json['id'])?.toString();
    return Customer(
      id: idVal,
      customerName: name,
      customerNumber: number,
      companyName: company,
      email: mail,
      emailId: mail,
      address: addr,
      city: c,
      pincode: pin,
      countryCode: cCode,
      state: json['state']?.toString(),
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : (json['lat'] is num ? (json['lat'] as num).toDouble() : null),
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : (json['lng'] is num ? (json['lng'] as num).toDouble() : null),
      radius: json['radius'] is num ? (json['radius'] as num).toDouble() : null,
      createdBy: json['createdBy']?.toString(),
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (id != null) '_id': id,
      'name': customerName,
      'customerName': customerName,
      if (customerNumber != null) ...{
        'mobile': customerNumber,
        'customerNumber': customerNumber,
      },
      if (companyName != null) 'companyName': companyName,
      if (effectiveEmail != null) ...{
        'email': effectiveEmail,
        'emailId': effectiveEmail,
      },
      'address': address,
      'city': city,
      if (state != null) 'state': state,
      'pinCode': pincode,
      'pincode': pincode,
      if (countryCode != null) 'countryCode': countryCode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (radius != null) 'radius': radius,
      'status': 'Assigned',
    };
  }
}
