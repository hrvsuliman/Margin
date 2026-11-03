import 'dates.dart';
import 'store.dart';

/// Record types (docs/SYNC.md, section 5).
abstract final class Kind {
  static const subject = 'subject';
  static const topic = 'topic';
  static const lesson = 'lesson';
  static const task = 'task';
  static const subtask = 'subtask';
  static const exam = 'exam';
  static const event = 'event';
  static const holiday = 'holiday';
  static const note = 'note';
  static const noteMeta = 'noteMeta';
  static const pin = 'pin';
  static const card = 'card';
  static const session = 'session';
  static const progress = 'progress';
  static const plan = 'plan';
  static const result = 'result';
  static const ink = 'ink';
}

/// Every field of the iPhone DTO with its default. Swift decodes the DTOs
/// strictly, so a record created here must contain all non-optional fields.
Map<String, dynamic> defaultsFor(String type) {
  final now = isoDate(DateTime.now());
  switch (type) {
    case Kind.subject:
      return {'name': '', 'colorKey': 'blue', 'teacher': '', 'room': '', 'notes': '', 'sortIndex': 0, 'createdAt': now};
    case Kind.topic:
      return {'title': '', 'details': '', 'sortIndex': 0, 'createdAt': now};
    case Kind.lesson:
      return {'weekday': 1, 'startMinute': 480, 'endMinute': 525, 'room': '', 'note': ''};
    case Kind.task:
      return {
        'title': '', 'details': '', 'kind': 'homework', 'priority': 1, 'status': 'open',
        'hasDueTime': false, 'estimatedMinutes': 0, 'createdAt': now,
      };
    case Kind.subtask:
      return {'title': '', 'isDone': false, 'sortIndex': 0};
    case Kind.exam:
      return {
        'title': '', 'kind': 'classTest', 'date': now, 'hasTime': false, 'durationMinutes': 90, 'room': '',
        'notes': '', 'reminderDaysBefore': 1, 'createdAt': now,
      };
    case Kind.event:
      return {
        'title': '', 'notes': '', 'location': '', 'start': now, 'end': now, 'isAllDay': false,
        'category': 'personal', 'recurrence': 'never', 'reminderMinutesBefore': -1, 'createdAt': now,
      };
    case Kind.holiday:
      return {'name': '', 'start': now, 'end': now};
    case Kind.note:
      return {
        'title': '', 'body': '', 'folder': '', 'noteDate': now, 'createdAt': now, 'updatedAt': now,
        'paper': 'lined', 'lineSpacingMM': 8.0, 'writingSize': 1.0, 'penColor': 'royalBlue', 'penWeight': 1.0,
        'marginTopMM': 20.0, 'marginBottomMM': 15.0, 'marginLeftMM': 20.0, 'marginRightMM': 15.0,
        'showMarginLine': true, 'showPageNumbers': true, 'showHeader': true, 'printPaper': true, 'seed': 1,
      };
    case Kind.noteMeta:
      return {'pinned': false, 'template': ''};
    case Kind.pin:
      return {'kind': 'sticky', 'title': '', 'text': '', 'url': '', 'color': 'mustard', 'sortIndex': 0, 'createdAt': now};
    case Kind.card:
      return {
        'front': '', 'back': '', 'createdAt': now, 'ease': 2.5, 'intervalDays': 0, 'repetitions': 0, 'lapses': 0,
        'due': now,
      };
    case Kind.session:
      return {
        'kind': 'free', 'status': 'planned', 'date': now, 'plannedMinutes': 30, 'actualMinutes': 0,
        'isPlanned': true, 'note': '',
      };
    case Kind.progress:
      return {'understanding': 0, 'completion': 0.0, 'importance': 1, 'estimatedMinutes': 60, 'updatedAt': now};
    case Kind.result:
      return {'score': 0.0, 'date': now, 'kind': 'cards'};
    case Kind.ink:
      return {'strokes': <dynamic>[], 'pageWidth': 1000, 'pageHeight': 1414, 'createdAt': now};
  }
  return {};
}

// ---------------------------------------------------------------- typed views

extension type Subject(Rec rec) {
  String get uid => rec.uid;
  String get name => rec.str('name');
  String get colorKey => rec.str('colorKey').isEmpty ? 'gray' : rec.str('colorKey');
  String get teacher => rec.str('teacher');
  String get room => rec.str('room');
  String get notes => rec.str('notes');
  int get sortIndex => rec.integer('sortIndex');
}

extension type Topic(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  String? get subject => rec.ref('subject');
  String? get parent => rec.ref('parent');
  int get sortIndex => rec.integer('sortIndex');
}

extension type Lesson(Rec rec) {
  String get uid => rec.uid;

  /// 1 = Monday … 7 = Sunday.
  int get weekday => rec.integer('weekday', 1);
  int get startMinute => rec.integer('startMinute', 480);
  int get endMinute => rec.integer('endMinute', 525);
  String get room => rec.str('room');
  String get note => rec.str('note');
  String? get subject => rec.ref('subject');
}

const taskKinds = {
  'homework': 'Hausaufgabe',
  'assignment': 'Abgabe',
  'presentation': 'Präsentation',
  'project': 'Projekt',
  'examPrep': 'Prüfungsvorbereitung',
  'general': 'Allgemein',
};
const taskPriorities = {0: 'Niedrig', 1: 'Mittel', 2: 'Hoch'};
const taskStatuses = {'open': 'Offen', 'inProgress': 'In Arbeit', 'done': 'Erledigt'};

extension type Task(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  String get details => rec.str('details');
  String get kind => taskKinds.containsKey(rec.str('kind')) ? rec.str('kind') : 'general';
  int get priority => rec.integer('priority', 1);
  String get status => taskStatuses.containsKey(rec.str('status')) ? rec.str('status') : 'open';
  bool get isDone => status == 'done';
  DateTime? get dueDate => parseIso(rec.data['dueDate']);
  bool get hasDueTime => rec.flag('hasDueTime');
  int get estimatedMinutes => rec.integer('estimatedMinutes');
  DateTime? get completedAt => parseIso(rec.data['completedAt']);
  DateTime get createdAt => parseIso(rec.data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(rec.updatedAt);
  String? get subject => rec.ref('subject');
  String? get exam => rec.ref('exam');

  /// The moment after which the task counts as overdue (as on the iPhone).
  DateTime? get deadline {
    final due = dueDate;
    if (due == null) return null;
    return hasDueTime ? due : addDays(startOfDay(due), 1);
  }

  bool isOverdue([DateTime? now]) {
    final d = deadline;
    return !isDone && d != null && !d.isAfter(now ?? DateTime.now());
  }
}

extension type Subtask(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  bool get isDone => rec.flag('isDone');
  int get sortIndex => rec.integer('sortIndex');
  String? get task => rec.ref('task');
}

const examKinds = {
  'classTest': 'Klassenarbeit',
  'klausur': 'Klausur',
  'test': 'Test',
  'oral': 'Mündliche Prüfung',
  'finalExam': 'Abschlussprüfung',
  'other': 'Prüfung',
};

extension type Exam(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  String get kind => examKinds.containsKey(rec.str('kind')) ? rec.str('kind') : 'other';
  DateTime get date => parseIso(rec.data['date']) ?? DateTime.now();
  bool get hasTime => rec.flag('hasTime');
  int get durationMinutes => rec.integer('durationMinutes', 90);
  String get room => rec.str('room');
  String get notes => rec.str('notes');
  String? get subject => rec.ref('subject');
}

const eventCategories = {
  'personal': 'Privat',
  'school': 'Schule',
  'project': 'Projekt',
  'presentation': 'Präsentation',
  'trip': 'Ausflug',
  'other': 'Sonstiges',
};
const recurrences = {
  'never': 'Nie',
  'daily': 'Täglich',
  'weekly': 'Wöchentlich',
  'biweekly': 'Alle 2 Wochen',
  'monthly': 'Monatlich',
  'yearly': 'Jährlich',
};

extension type CalEvent(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  String get notes => rec.str('notes');
  String get location => rec.str('location');
  DateTime get start => parseIso(rec.data['start']) ?? DateTime.now();

  /// For all-day events: the start of the last day (inclusive).
  DateTime get end => parseIso(rec.data['end']) ?? start;
  bool get isAllDay => rec.flag('isAllDay');
  String get category => eventCategories.containsKey(rec.str('category')) ? rec.str('category') : 'other';
  String get recurrence => recurrences.containsKey(rec.str('recurrence')) ? rec.str('recurrence') : 'never';
  DateTime? get recurrenceEnd => parseIso(rec.data['recurrenceEnd']);
  String? get subject => rec.ref('subject');
}

extension type Holiday(Rec rec) {
  String get uid => rec.uid;
  String get name => rec.str('name');
  DateTime get start => parseIso(rec.data['start']) ?? DateTime.now();
  DateTime get end => parseIso(rec.data['end']) ?? start;

  bool contains(DateTime day) {
    final d = startOfDay(day);
    return !d.isBefore(startOfDay(start)) && !d.isAfter(startOfDay(end));
  }
}

extension type Note(Rec rec) {
  String get uid => rec.uid;
  String get title => rec.str('title');
  String get body => rec.str('body');
  String get folder => rec.str('folder');
  DateTime get noteDate => parseIso(rec.data['noteDate']) ?? DateTime.now();
  DateTime get updatedAt => parseIso(rec.data['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(rec.updatedAt);
  String get paper => rec.str('paper').isEmpty ? 'lined' : rec.str('paper');
  String get penColor => rec.str('penColor').isEmpty ? 'royalBlue' : rec.str('penColor');
  String? get subject => rec.ref('subject');
  String? get topic => rec.ref('topic');
  String? get exam => rec.ref('exam');

  String get displayTitle => title.trim().isEmpty ? 'Ohne Titel' : title.trim();
}

extension type NoteMeta(Rec rec) {
  String? get note => rec.ref('note');
  String? get parent => rec.ref('parent');
  bool get pinned => rec.flag('pinned');
}

const pinKinds = {'note': 'Notiz', 'video': 'Video', 'link': 'Link', 'photo': 'Foto', 'sticky': 'Zettel'};

extension type Pin(Rec rec) {
  String get uid => rec.uid;
  String? get subject => rec.ref('subject');
  String get kind => pinKinds.containsKey(rec.str('kind')) ? rec.str('kind') : 'sticky';
  String get title => rec.str('title');
  String get text => rec.str('text');
  String get url => rec.str('url').trim();
  String? get note => rec.ref('note');
  String get color => rec.str('color').isEmpty ? 'mustard' : rec.str('color');
  int get sortIndex => rec.integer('sortIndex');

  /// Base64 JPEG, if this is a photo.
  String? get photo => rec.ref('photo');
}

extension type Flashcard(Rec rec) {
  String get uid => rec.uid;
  String? get subject => rec.ref('subject');
  String? get topic => rec.ref('topic');
  String? get note => rec.ref('note');
  String get front => rec.str('front');
  String get back => rec.str('back');
  double get ease => rec.number('ease', 2.5);
  int get intervalDays => rec.integer('intervalDays');
  int get repetitions => rec.integer('repetitions');
  int get lapses => rec.integer('lapses');
  DateTime get due => parseIso(rec.data['due']) ?? DateTime.now();
  DateTime? get lastReviewed => parseIso(rec.data['lastReviewed']);

  bool isDue([DateTime? now]) => !due.isAfter(now ?? DateTime.now());
}

extension type StudySession(Rec rec) {
  String get uid => rec.uid;
  String? get exam => rec.ref('exam');
  String? get topic => rec.ref('topic');
  String? get subject => rec.ref('subject');
  String get kind => rec.str('kind');
  String get status => rec.str('status');
  DateTime get date => parseIso(rec.data['date']) ?? DateTime.now();
  int get plannedMinutes => rec.integer('plannedMinutes', 30);
  int get actualMinutes => rec.integer('actualMinutes');
  DateTime? get completedAt => parseIso(rec.data['completedAt']);
}

extension type TopicProgress(Rec rec) {
  String? get topic => rec.ref('topic');
  int get understanding => rec.integer('understanding');
  double get completion => rec.number('completion');
  int get importance => rec.integer('importance', 1);
  DateTime? get lastStudied => parseIso(rec.data['lastStudied']);
}

extension type ExamPlan(Rec rec) {
  String? get exam => rec.ref('exam');
  List<String> get topics => [for (final t in rec.data['topics'] as List? ?? const []) if (t is String) t];
}

extension type PracticeResult(Rec rec) {
  String? get topic => rec.ref('topic');
  double get score => rec.number('score');
  DateTime get date => parseIso(rec.data['date']) ?? DateTime.now();
}

extension type Ink(Rec rec) {
  String get uid => rec.uid;
  String? get note => rec.ref('note');
  List<dynamic> get strokes => rec.data['strokes'] as List? ?? const [];
}

// ---------------------------------------------------------------- queries

extension Queries on Store {
  Rec add(String type, Map<String, dynamic> fields) => create(type, {...defaultsFor(type), ...fields});

  List<Subject> get subjects => records(Kind.subject).map(Subject.new).toList()
    ..sort((a, b) => a.sortIndex != b.sortIndex ? a.sortIndex.compareTo(b.sortIndex) : a.name.compareTo(b.name));

  Subject? subject(String? uid) {
    final rec = byUid(uid);
    return rec != null && rec.type == Kind.subject ? Subject(rec) : null;
  }

  List<Topic> topicsOf(String subjectUid) =>
      records(Kind.topic).map(Topic.new).where((t) => t.subject == subjectUid).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  List<Lesson> get lessons => records(Kind.lesson).map(Lesson.new).toList()
    ..sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : a.startMinute.compareTo(b.startMinute));

  List<Task> get tasks => records(Kind.task).map(Task.new).toList();

  List<Subtask> subtasksOf(String taskUid) =>
      records(Kind.subtask).map(Subtask.new).where((s) => s.task == taskUid).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  List<Exam> get exams => records(Kind.exam).map(Exam.new).toList()..sort((a, b) => a.date.compareTo(b.date));

  Exam? exam(String? uid) {
    final rec = byUid(uid);
    return rec != null && rec.type == Kind.exam ? Exam(rec) : null;
  }

  List<CalEvent> get events => records(Kind.event).map(CalEvent.new).toList();
  List<Holiday> get holidays => records(Kind.holiday).map(Holiday.new).toList();

  List<Note> get notes => records(Kind.note).map(Note.new).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Note? note(String? uid) {
    final rec = byUid(uid);
    return rec != null && rec.type == Kind.note ? Note(rec) : null;
  }

  List<Pin> pinsOf(String subjectUid) =>
      records(Kind.pin).map(Pin.new).where((p) => p.subject == subjectUid).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  List<Flashcard> get cards => records(Kind.card).map(Flashcard.new).toList();
  List<StudySession> get sessions => records(Kind.session).map(StudySession.new).toList();

  Ink? inkOf(String noteUid) {
    for (final rec in records(Kind.ink)) {
      if (rec.ref('note') == noteUid) return Ink(rec);
    }
    return null;
  }

  /// Exam title as on the iPhone: own title, otherwise "Klassenarbeit Mathematik".
  String examTitle(Exam exam) {
    final own = exam.title.trim();
    if (own.isNotEmpty) return own;
    final name = subject(exam.subject)?.name;
    return name == null ? examKinds[exam.kind]! : '${examKinds[exam.kind]} $name';
  }
}
