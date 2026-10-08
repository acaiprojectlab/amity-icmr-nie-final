import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/auth_models.dart';
import '../database/app_database.dart';
import '../ml/onnx_predictor.dart';
import '../models/metadata_models.dart';
import '../models/patient_record.dart';
import '../models/prediction_result.dart';
import '../services/reference_data_service.dart';
import '../sync/sync_store.dart';

class AppProvider extends ChangeNotifier {
  final ReferenceDataService _refService = ReferenceDataService.instance;
  final AppDatabase _db = AppDatabase.instance;
  OnnxPredictor? _predictor;

  bool _isInitializing = true;
  String? _initError;

  // Active Patient Intake Form State
  DateTime _dateOfCollection = DateTime.now();
  String _patientName = '';
  String _patientMrdId = '';
  String _hospital = 'MMC';
  String _department = 'Medicine';
  String _departmentOther = '';
  DateTime _dateOfAdmission = DateTime.now();
  String _mobileNo = '';
  String _addressLine = '';
  String _selectedState = 'Tamil Nadu';
  int _stateEncoded = 29;
  String _selectedDistrict = '';
  int _districtEncoded = 0;
  String _subdistrict = '';
  String _pinCode = '';
  int _age = 0;
  int _sex = 0; // 0: Female, 1: Male, 2: Other
  int _patientType = 0; // 0: Outpatient, 1: Inpatient
  DateTime _onsetOfIllness = DateTime.now();
  int _syndromeEncoded = 0;
  String _syndromeName = 'ARI/Influenza Like Illness (ILI)';
  final Map<String, int> _symptoms = {};

  // Inference state
  bool _isPredicting = false;
  FullPredictionResult? _currentPrediction;
  PatientRecord? _lastEnrolledRecord;

  // Records & Dashboard State
  List<PatientRecord> _records = [];
  DashboardMetrics _metrics = _emptyMetrics();
  String _statusFilter = 'All'; // 'All', 'Pending', 'Completed'
  String _searchQuery = '';
  String? _filterHospital;
  String? _filterDepartment;
  bool _isLoadingRecords = false;

  // Role-based access (set from the signed-in session by the auth gate).
  // Patient records and case metrics are admin-only, as on the web; for
  // anyone else they are never loaded into memory, and record-changing
  // actions refuse to run.
  String? _accessUserId;
  String _accessEmail = '';
  bool _canViewRecords = false;

  /// Called after any change that needs uploading (wired to RecordSyncer).
  VoidCallback? onLocalChange;

  // Getters
  bool get isInitializing => _isInitializing;
  String? get initError => _initError;
  bool get isPredicting => _isPredicting;
  FullPredictionResult? get currentPrediction => _currentPrediction;
  PatientRecord? get lastEnrolledRecord => _lastEnrolledRecord;
  List<PatientRecord> get records => _records;
  DashboardMetrics get metrics => _metrics;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;
  bool get isLoadingRecords => _isLoadingRecords;
  bool get canViewRecords => _canViewRecords;

  DateTime get dateOfCollection => _dateOfCollection;
  String get patientName => _patientName;
  String get patientMrdId => _patientMrdId;
  String get hospital => _hospital;
  String get department => _department;
  String get departmentOther => _departmentOther;
  DateTime get dateOfAdmission => _dateOfAdmission;
  String get mobileNo => _mobileNo;
  String get addressLine => _addressLine;
  String get selectedState => _selectedState;
  int get stateEncoded => _stateEncoded;
  String get selectedDistrict => _selectedDistrict;
  int get districtEncoded => _districtEncoded;
  String get subdistrict => _subdistrict;
  String get pinCode => _pinCode;
  int get age => _age;
  int get sex => _sex;
  int get patientType => _patientType;
  DateTime get onsetOfIllness => _onsetOfIllness;
  int get durationOfIllness =>
      mathMax(0, _dateOfAdmission.difference(_onsetOfIllness).inDays);
  int get syndromeEncoded => _syndromeEncoded;
  String get syndromeName => _syndromeName;
  Map<String, int> get symptoms => Map.unmodifiable(_symptoms);

  int mathMax(int a, int b) => a > b ? a : b;

  static DashboardMetrics _emptyMetrics() => DashboardMetrics(
        enrolled: 0,
        drCompleted: 0,
        drPending: 0,
        daily: 0,
        weekly: 0,
        monthly: 0,
      );

  AppProvider() {
    initApp();
  }

  Future<void> initApp() async {
    _isInitializing = true;
    _initError = null;
    notifyListeners();

    try {
      await _refService.loadAll();

      // Initialize all symptoms with 0
      for (final s in _refService.allSymptoms) {
        _symptoms[s] = 0;
      }

      // Initialize default state & district
      if (_refService.statesMap.containsKey('Tamil Nadu')) {
        final tn = _refService.statesMap['Tamil Nadu']!;
        _selectedState = tn.stateName;
        _stateEncoded = tn.stateEncoded;
        if (tn.districts.isNotEmpty) {
          _selectedDistrict = tn.districts.first.name;
          _districtEncoded = tn.districts.first.encoded;
        }
      }

      // Initialize ONNX Predictor
      _predictor = OnnxPredictor(modelConfig: _refService.modelConfig);
      await _predictor!.initialize();

      // Load initial dashboard metrics & records
      await refreshDashboard();

      _isInitializing = false;
      notifyListeners();
    } catch (e) {
      _initError = e.toString();
      _isInitializing = false;
      notifyListeners();
    }
  }

  // --- Role-based access ---

  /// Apply the signed-in person's access. A change of person (including
  /// sign-out) clears the intake form so the next user never sees the
  /// previous patient's details.
  void applyAccess(AuthSession? session) {
    final userId = session?.userId;
    _accessEmail = session?.email ?? '';
    if (userId != _accessUserId) {
      _accessUserId = userId;
      resetForm();
    }
    final canView =
        session != null && roleCanOpen(session.role, AppPage.records);
    if (canView == _canViewRecords) return;
    _canViewRecords = canView;
    if (canView) {
      refreshDashboard();
    } else {
      _records = [];
      _metrics = _emptyMetrics();
      notifyListeners();
    }
  }

  void _requireRecordsAccess() {
    if (!_canViewRecords) {
      throw StateError('Administrator access is required for patient records.');
    }
  }

  // --- Form Mutation Methods ---
  void setDateOfCollection(DateTime dt) {
    _dateOfCollection = dt;
    notifyListeners();
  }

  void setPatientName(String val) {
    _patientName = val;
    notifyListeners();
  }

  void setPatientMrdId(String val) {
    _patientMrdId = val;
    notifyListeners();
  }

  void setHospital(String val) {
    _hospital = val;
    notifyListeners();
  }

  void setDepartment(String val) {
    _department = val;
    notifyListeners();
  }

  void setDepartmentOther(String val) {
    _departmentOther = val;
    notifyListeners();
  }

  void setDateOfAdmission(DateTime dt) {
    _dateOfAdmission = dt;
    notifyListeners();
  }

  void setMobileNo(String val) {
    _mobileNo = val;
    notifyListeners();
  }

  void setAddressLine(String val) {
    _addressLine = val;
    notifyListeners();
  }

  void setState(String stateName) {
    if (_refService.statesMap.containsKey(stateName)) {
      final s = _refService.statesMap[stateName]!;
      _selectedState = s.stateName;
      _stateEncoded = s.stateEncoded;
      if (s.districts.isNotEmpty) {
        _selectedDistrict = s.districts.first.name;
        _districtEncoded = s.districts.first.encoded;
      } else {
        _selectedDistrict = '';
        _districtEncoded = 0;
      }
      notifyListeners();
    }
  }

  void setDistrict(String districtName) {
    final state = _refService.statesMap[_selectedState];
    if (state != null) {
      final d = state.districts.firstWhere(
        (dist) => dist.name == districtName,
        orElse: () => state.districts.first,
      );
      _selectedDistrict = d.name;
      _districtEncoded = d.encoded;
      notifyListeners();
    }
  }

  void setSubdistrict(String val) {
    _subdistrict = val;
    notifyListeners();
  }

  void setPinCode(String val) {
    _pinCode = val;
    notifyListeners();
  }

  void setAge(int val) {
    _age = val;
    notifyListeners();
  }

  void setSex(int val) {
    _sex = val;
    notifyListeners();
  }

  void setPatientType(int val) {
    _patientType = val;
    notifyListeners();
  }

  void setOnsetOfIllness(DateTime dt) {
    _onsetOfIllness = dt;
    notifyListeners();
  }

  void setSyndrome(SyndromeOption option) {
    _syndromeEncoded = option.encodedValue;
    _syndromeName = option.overallSyndrome;
    notifyListeners();
  }

  void toggleSymptom(String symptomKey) {
    final cur = _symptoms[symptomKey] ?? 0;
    _symptoms[symptomKey] = cur == 1 ? 0 : 1;
    notifyListeners();
  }

  void setSymptomValue(String symptomKey, bool isPresent) {
    _symptoms[symptomKey] = isPresent ? 1 : 0;
    notifyListeners();
  }

  void resetForm() {
    _dateOfCollection = DateTime.now();
    _patientName = '';
    _patientMrdId = '';
    _hospital = 'MMC';
    _department = 'Medicine';
    _departmentOther = '';
    _dateOfAdmission = DateTime.now();
    _mobileNo = '';
    _addressLine = '';
    _subdistrict = '';
    _pinCode = '';
    _age = 0;
    _sex = 0;
    _patientType = 0;
    _onsetOfIllness = DateTime.now();
    _syndromeEncoded = 0;
    _syndromeName = 'ARI/Influenza Like Illness (ILI)';

    for (final s in _refService.allSymptoms) {
      _symptoms[s] = 0;
    }

    _currentPrediction = null;
    _lastEnrolledRecord = null;
    notifyListeners();
  }

  // --- Inference Action ---
  Future<FullPredictionResult> runPrediction() async {
    if (_predictor == null) {
      throw Exception("Predictor engine is not initialized");
    }

    _isPredicting = true;
    notifyListeners();

    try {
      final dfFmt = DateFormat('dd-MM-yyyy');

      final patientData = {
        'age': _age,
        'SEX': _sex,
        'PATIENTTYPE': _patientType,
        'durationofillness': durationOfIllness,
        'month': _onsetOfIllness.month,
        'year': 2015,
        'labstate': _stateEncoded,
        'lab_state': _stateEncoded,
        'districtencoded': _districtEncoded,
        'district_encoded': _districtEncoded,
        'Syndrome_encoded': _syndromeEncoded,
        'syndrome': _syndromeEncoded,
        'syndrome_name': _syndromeName,
        'date_of_collection': dfFmt.format(_dateOfCollection),
        'date_of_admission': dfFmt.format(_dateOfAdmission),
        'onset_of_illness': dfFmt.format(_onsetOfIllness),
        ..._symptoms,
      };

      final result = await _predictor!.predict(patientData);
      _currentPrediction = result;
      _isPredicting = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isPredicting = false;
      notifyListeners();
      rethrow;
    }
  }

  // --- Enrolment Action ---
  Future<PatientRecord> enrolPatient() async {
    if (_currentPrediction == null) {
      throw Exception("No prediction available to enrol");
    }

    final dfFmt = DateFormat('dd-MM-yyyy');

    // Generate atomic sequential IDs
    // Temporary IDs until the record is uploaded; the shared database then
    // assigns the official ones (P042, M17...) from the web's counters, so
    // phones and the web never hand out the same number.
    final patientId = 'TMP-${await _db.getNextPatientId()}';
    final localStudyId = await _db.getNextStudyId(_hospital);
    final studyId = localStudyId.isEmpty ? '' : 'TMP-$localStudyId';

    final top5 = _currentPrediction!.top5Predictions;

    final record = PatientRecord(
      patientId: patientId,
      patientStudyId: studyId,
      patientMrdId: _patientMrdId.trim(),
      patientName: _patientName.trim(),
      hospital: _hospital,
      department: _department,
      departmentSpecification: _department == 'Other' ? _departmentOther : '',
      dateOfCollection: dfFmt.format(_dateOfCollection),
      dateOfAdmission: dfFmt.format(_dateOfAdmission),
      mobileNo: _mobileNo.trim(),
      addressLine: _addressLine.trim(),
      stateName: _selectedState,
      stateEncoded: _stateEncoded,
      districtName: _selectedDistrict,
      districtEncoded: _districtEncoded,
      subdistrict: _subdistrict.trim(),
      pinCode: _pinCode.trim(),
      age: _age,
      sex: _sex,
      patientType: _patientType,
      onsetOfIllness: dfFmt.format(_onsetOfIllness),
      durationOfIllness: durationOfIllness,
      syndromeEncoded: _syndromeEncoded,
      syndromeName: _syndromeName,
      symptoms: Map.from(_symptoms),
      predictedVirusName: _currentPrediction!.predictedVirusName,
      predictionConfidence: _currentPrediction!.confidence,
      top1Virus: top5.isNotEmpty ? top5[0].virusName : '',
      top1Confidence: top5.isNotEmpty ? top5[0].confidence : 0.0,
      top2Virus: top5.length > 1 ? top5[1].virusName : '',
      top2Confidence: top5.length > 1 ? top5[1].confidence : 0.0,
      top3Virus: top5.length > 2 ? top5[2].virusName : '',
      top3Confidence: top5.length > 2 ? top5[2].confidence : 0.0,
      top4Virus: top5.length > 3 ? top5[3].virusName : '',
      top4Confidence: top5.length > 3 ? top5[3].confidence : 0.0,
      top5Virus: top5.length > 4 ? top5[4].virusName : '',
      top5Confidence: top5.length > 4 ? top5[4].confidence : 0.0,
      createdAt: DateTime.now().toIso8601String(),
      clientRecordId: newRecordId(),
      enrolledBy: _accessEmail,
    );

    final insertedId = await _db.insertPatient(record);
    final savedRecord = (await _db.getPatientById(insertedId))!;

    _lastEnrolledRecord = savedRecord;
    await refreshDashboard();
    notifyListeners();
    onLocalChange?.call();
    return savedRecord;
  }

  /// Uploads can replace temporary IDs with official ones: reload what the
  /// screens show.
  Future<void> reloadAfterSync() async {
    final lastId = _lastEnrolledRecord?.id;
    if (lastId != null) {
      _lastEnrolledRecord = await _db.getPatientById(lastId) ?? _lastEnrolledRecord;
    }
    await refreshDashboard();
    notifyListeners();
  }

  // --- Doctor Recommendation Update ---
  Future<void> updateDoctorRecommendation({
    required int recordId,
    required String labId,
    required List<String> recommendedPathogens,
  }) async {
    _requireRecordsAccess();
    await _db.updateDoctorRecommendation(
      id: recordId,
      labId: labId.trim(),
      confirmedPathogen: recommendedPathogens.join(', '),
    );
    await refreshDashboard();
    onLocalChange?.call();
  }

  // --- Soft-Delete Record ---
  Future<void> softDeleteRecord(int recordId) async {
    _requireRecordsAccess();
    await _db.softDeletePatient(recordId);
    await refreshDashboard();
    onLocalChange?.call();
  }

  // --- Filter & Search Records ---
  void setStatusFilter(String status) {
    _statusFilter = status;
    refreshRecords();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    refreshRecords();
  }

  void setHospitalFilter(String? hosp) {
    _filterHospital = hosp;
    refreshRecords();
  }

  void setDepartmentFilter(String? dept) {
    _filterDepartment = dept;
    refreshRecords();
  }

  Future<void> refreshRecords() async {
    if (!_canViewRecords) {
      _records = [];
      return;
    }
    _isLoadingRecords = true;
    notifyListeners();

    _records = await _db.getPatients(
      status: _statusFilter,
      searchQuery: _searchQuery,
      hospital: _filterHospital,
      department: _filterDepartment,
    );

    _isLoadingRecords = false;
    notifyListeners();
  }

  Future<void> refreshDashboard() async {
    if (!_canViewRecords) {
      _metrics = _emptyMetrics();
      _records = [];
      return;
    }
    _metrics = await _db.getDashboardMetrics();
    await refreshRecords();
  }

  @override
  void dispose() {
    _predictor?.dispose();
    super.dispose();
  }
}
