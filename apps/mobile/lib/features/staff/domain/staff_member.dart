import 'package:equatable/equatable.dart';

class StaffMember extends Equatable {
  const StaffMember({
    required this.membershipId,
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.branchIds,
  });

  final String membershipId;
  final String userId;
  final String displayName;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;
  final List<String> branchIds;

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      membershipId: json['membership_id'].toString(),
      userId: json['user_id'].toString(),
      displayName: json['display_name'].toString(),
      email: json['email'].toString(),
      phone: json['phone']?.toString(),
      role: json['role'].toString(),
      isActive: json['is_active'] as bool? ?? false,
      branchIds: (json['branch_ids'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [
        membershipId,
        userId,
        displayName,
        email,
        phone,
        role,
        isActive,
        branchIds,
      ];
}

class StaffBranch extends Equatable {
  const StaffBranch({
    required this.id,
    required this.name,
    required this.code,
    required this.location,
    required this.isMain,
  });

  final String id;
  final String name;
  final String code;
  final String? location;
  final bool isMain;

  factory StaffBranch.fromJson(Map<String, dynamic> json) {
    return StaffBranch(
      id: json['id'].toString(),
      name: json['name'].toString(),
      code: json['code'].toString(),
      location: json['location']?.toString(),
      isMain: json['is_main'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, name, code, location, isMain];
}
