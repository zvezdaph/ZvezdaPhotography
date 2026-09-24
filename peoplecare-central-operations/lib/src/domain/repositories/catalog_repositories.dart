import '../entities/facility.dart';
import '../entities/patient.dart';
import '../entities/service_type.dart';

/// Strutture PeopleCare.
abstract interface class FacilityRepository {
  Future<List<Facility>> listFacilities();

  Future<Facility> getFacility(String id);

  Future<Facility> createFacility(FacilityDraft draft);

  Future<Facility> updateFacility(
    String id,
    FacilityDraft draft, {
    required int expectedVersion,
  });
}

/// Catalogo delle tipologie di servizio.
abstract interface class ServiceTypeRepository {
  Future<List<ServiceType>> listServiceTypes();

  Future<ServiceType> getServiceType(String id);

  Future<ServiceType> createServiceType(ServiceTypeDraft draft);

  Future<ServiceType> updateServiceType(
    String id,
    ServiceTypeDraft draft, {
    required int expectedVersion,
  });
}

/// Anagrafica pazienti (sola lettura per la Centrale Operativa).
abstract interface class PatientRepository {
  /// Ricerca per nome, cognome o codice.
  Future<List<Patient>> searchPatients(
    String text, {
    String? facilityId,
    int limit = 20,
  });

  Future<Patient> getPatient(String id);
}
