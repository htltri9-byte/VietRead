/// Model `Genre` — khớp JSON của `GET /genres`: `{ id, name }`.
class Genre {
  const Genre({required this.id, required this.name});

  final int id;
  final String name;

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};
}
