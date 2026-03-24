// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Customer _$CustomerFromJson(Map<String, dynamic> json) => Customer(
  id: json['_id'] as String?,
  customerName: json['customerName'] as String,
  customerNumber: json['customerNumber'] as String?,
  companyName: json['companyName'] as String?,
  email: json['email'] as String?,
  emailId: json['emailId'] as String?,
  address: json['address'] as String,
  city: json['city'] as String,
  pincode: json['pincode'] as String,
  countryCode: json['countryCode'] as String?,
  createdBy: json['createdBy'] as String?,
  createdAt: json['createdAt'] as String?,
  updatedAt: json['updatedAt'] as String?,
);

Map<String, dynamic> _$CustomerToJson(Customer instance) => <String, dynamic>{
  '_id': ?instance.id,
  'customerName': instance.customerName,
  'customerNumber': ?instance.customerNumber,
  'companyName': ?instance.companyName,
  'email': ?instance.email,
  'emailId': ?instance.emailId,
  'address': instance.address,
  'city': instance.city,
  'pincode': instance.pincode,
  'countryCode': ?instance.countryCode,
  'createdBy': ?instance.createdBy,
  'createdAt': ?instance.createdAt,
  'updatedAt': ?instance.updatedAt,
};
