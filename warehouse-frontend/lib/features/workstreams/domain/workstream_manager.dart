/// A `{id, userId, workstreamId, createdAt, user}` assignment row — mirrors
/// `workstream_managers` (`GET/POST/DELETE /workstreams/:id/managers`). A
/// user with ANY such row is scoped, for catalogue mutations (categories +
/// products), to only their assigned workstream(s); see CLAUDE.md / the
/// backend's `WorkstreamManagersService` doc comment for the full design.
class WorkstreamManager {
  const WorkstreamManager({
    required this.id,
    required this.userId,
    required this.workstreamId,
    required this.createdAt,
    required this.userEmail,
    required this.userFullName,
  });

  final String id;
  final String userId;
  final String workstreamId;
  final DateTime createdAt;
  final String userEmail;
  final String userFullName;

  factory WorkstreamManager.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return WorkstreamManager(
      id: json['id'] as String,
      userId: json['userId'] as String,
      workstreamId: json['workstreamId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      userEmail: user['email'] as String,
      userFullName: user['fullName'] as String,
    );
  }
}

/// A `{id, workstreamId, createdAt, workstream: {id, name, code}}` row —
/// the OTHER direction (`GET /users/me/workstreams`, "which workstreams am
/// I scoped to"), a lighter shape than [WorkstreamManager] since it embeds
/// the workstream ref instead of the user ref.
class MyWorkstreamAssignment {
  const MyWorkstreamAssignment({
    required this.id,
    required this.workstreamId,
    required this.workstreamName,
    required this.workstreamCode,
  });

  final String id;
  final String workstreamId;
  final String workstreamName;
  final String workstreamCode;

  factory MyWorkstreamAssignment.fromJson(Map<String, dynamic> json) {
    final workstream = json['workstream'] as Map<String, dynamic>;
    return MyWorkstreamAssignment(
      id: json['id'] as String,
      workstreamId: json['workstreamId'] as String,
      workstreamName: workstream['name'] as String,
      workstreamCode: workstream['code'] as String,
    );
  }
}
