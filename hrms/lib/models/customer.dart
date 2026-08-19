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
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
  Map<String, dynamic> toJson() => _$CustomerToJson(this);

  Customer copyWith({
    String? id,
    String? customerName,
    String? customerNumber,
    String? companyName,
    String? email,
    String? emailId,
    String? address,
    String? city,
    String? pincode,
    String? countryCode,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerNumber: customerNumber ?? this.customerNumber,
      companyName: companyName ?? this.companyName,
      email: email ?? this.email,
      emailId: emailId ?? this.emailId,
      address: address ?? this.address,
      city: city ?? this.city,
      pincode: pincode ?? this.pincode,
      countryCode: countryCode ?? this.countryCode,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
