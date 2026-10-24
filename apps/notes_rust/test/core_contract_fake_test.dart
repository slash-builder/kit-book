import 'package:notes_rust/core/fake_notes_core.dart';

import 'support/contract.dart';

void main() => coreContract('in-memory fake', (device) async => FakeNotesCore(device: device));
