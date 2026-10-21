import 'package:flutter_test/flutter_test.dart';
import 'package:face_att/models/user.dart';

void main() {
  test('User serialization and initialization test', () {
    final user = User(
      registerNumber: '23BRS1001',
      name: 'John Doe',
      email: 'john@example.com',
      phone: '1234567890',
      array: List.filled(512, 0.1),
    );

    final map = user.toMap();
    expect(map['register_number'], '23BRS1001');
    expect(map['name'], 'John Doe');
    expect((map['array'] as List).length, 512);

    final fromMap = User.fromMap(map);
    expect(fromMap.registerNumber, '23BRS1001');
    expect(fromMap.name, 'John Doe');
    expect(fromMap.array?.length, 512);
  });
}
