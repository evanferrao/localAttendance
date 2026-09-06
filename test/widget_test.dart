import 'package:flutter_test/flutter_test.dart';
import 'package:face_att/models/user.dart';

void main() {
  test('User serialization and initialization test', () {
    final user = User(
      id: 'USER_101',
      name: 'John Doe',
      email: 'john@example.com',
      phone: '1234567890',
      array: List.filled(512, 0.1),
    );

    final map = user.toMap();
    expect(map['id'], 'USER_101');
    expect(map['name'], 'John Doe');
    expect((map['array'] as List).length, 512);

    final fromMap = User.fromMap(map);
    expect(fromMap.id, 'USER_101');
    expect(fromMap.name, 'John Doe');
    expect(fromMap.array?.length, 512);
  });
}
