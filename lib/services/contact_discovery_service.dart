import '../models/app_user.dart';
import '../repositories/user_repository.dart';
import 'identity_service.dart';

class DiscoveredContact {
  final String phoneNumber; // original from device (never stored on server)
  final AppUser user;

  const DiscoveredContact({required this.phoneNumber, required this.user});
}

class ContactDiscoveryService {
  final UserRepository _userRepo;

  ContactDiscoveryService({required UserRepository userRepo})
      : _userRepo = userRepo;

  /// Given a list of phone numbers (E.164 format from device contacts),
  /// return the SecureChat users that match — without sending raw numbers
  /// to Firestore. Processes in batches of 10.
  Future<List<DiscoveredContact>> discoverContacts(
      List<String> phoneNumbers) async {
    final results = <DiscoveredContact>[];

    for (var i = 0; i < phoneNumbers.length; i += 10) {
      final batch = phoneNumbers.sublist(
        i,
        (i + 10) > phoneNumbers.length ? phoneNumbers.length : i + 10,
      );

      for (final phone in batch) {
        final hash = IdentityService.hashPhone(phone);
        final users = await _userRepo.searchUsersByPhoneHash(hash);
        for (final u in users) {
          results.add(DiscoveredContact(phoneNumber: phone, user: u));
        }
      }
    }

    return results;
  }
}
