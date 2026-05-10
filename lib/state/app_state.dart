import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/construction_type.dart';
import '../models/drawing.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import '../models/user_mode.dart';
import '../services/composition_planner.dart';
import '../services/drawing_generator.dart';
import '../storage/project_repository.dart';
import '../storage/settings_repository.dart';

/// Глобальное состояние приложения.
///
/// Хранит выбранный режим и список проектов в памяти, делегируя
/// долговременное хранение репозиториям. На любое изменение (создание,
/// переименование, удаление, правка проекта) вызывает [notifyListeners],
/// чтобы UI автоматически перерисовался — для этого используется пакет
/// `provider`.
class AppState extends ChangeNotifier {
  AppState({
    required SettingsRepository settingsRepository,
    required ProjectRepository projectRepository,
  })  : _settings = settingsRepository,
        _projects = projectRepository {
    _mode = _settings.loadMode() ?? UserMode.designer;
    _hintsEnabled = _settings.loadHintsEnabled();
    _organization = _settings.loadOrganization();
    _projectList = _projects.loadAll();
  }

  final SettingsRepository _settings;
  final ProjectRepository _projects;
  static const _uuid = Uuid();

  UserMode? _mode;
  List<HouseProject> _projectList = [];

  /// Глобальный флаг автопоказа обучающих подсказок. Сохраняется в
  /// SharedPreferences. Сбрасывать «показано в этой сессии» отдельно нет
  /// смысла — это in-memory множество [_hintsShownThisSession].
  bool _hintsEnabled = true;

  /// Реквизиты организации для штампа чертежей. Меняются через
  /// экран «Настройки» → «Организация». При пустом `companyName`
  /// штамп подставляет дефолт «Конструктор строений».
  OrganizationSettings _organization = const OrganizationSettings();

  /// Множество ключей экранов, чьи подсказки уже автоматически
  /// показывались в текущей сессии браузера/приложения. Перезагрузка
  /// страницы сбрасывает множество — это и есть «вести нового
  /// пользователя за руку при каждом заходе».
  final Set<String> _hintsShownThisSession = {};

  UserMode? get mode => _mode;
  bool get hasMode => _mode != null;

  bool get hintsEnabled => _hintsEnabled;

  Future<void> setHintsEnabled(bool value) async {
    if (_hintsEnabled == value) return;
    _hintsEnabled = value;
    await _settings.saveHintsEnabled(value);
    notifyListeners();
  }

  OrganizationSettings get organization => _organization;

  Future<void> setOrganization(OrganizationSettings value) async {
    _organization = value;
    await _settings.saveOrganization(value);
    notifyListeners();
  }

  /// Должен ли экран `key` автоматически показать свою подсказку при
  /// открытии. `true`, только если автопоказ включён глобально и в этой
  /// сессии этот экран ещё не показывал подсказку.
  bool shouldAutoShowHint(String key) {
    return _hintsEnabled && !_hintsShownThisSession.contains(key);
  }

  /// Пометить, что подсказка экрана `key` уже была показана в этой
  /// сессии — больше не выпрыгивать при возврате на тот же экран.
  void markHintShown(String key) {
    _hintsShownThisSession.add(key);
  }

  List<HouseProject> get projects =>
      List.unmodifiable(_projectList..sort(_byUpdatedDesc));

  Future<void> setMode(UserMode mode) async {
    _mode = mode;
    await _settings.saveMode(mode);
    notifyListeners();
  }

  Future<HouseProject> createProject({
    required String name,
    required ConstructionType type,
  }) async {
    final now = DateTime.now();
    final project = HouseProject(
      id: _uuid.v4(),
      name: name,
      constructionType: type,
      createdAt: now,
      updatedAt: now,
    );
    _projectList.add(project);
    await _persist();
    notifyListeners();
    return project;
  }

  Future<void> saveProject(HouseProject project) async {
    project.touch();
    final i = _projectList.indexWhere((p) => p.id == project.id);
    if (i == -1) {
      _projectList.add(project);
    } else {
      _projectList[i] = project;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    _projectList.removeWhere((p) => p.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> renameProject(String id, String newName) async {
    final i = _projectList.indexWhere((p) => p.id == id);
    if (i == -1) return;
    _projectList[i].name = newName;
    _projectList[i].touch();
    await _persist();
    notifyListeners();
  }

  /// Применить к проекту состав сооружения, рассчитанный движком правил
  /// на основе технического задания. Перетирает текущий выбор по фундаменту/стенам/крыше.
  ///
  /// Используется в режиме «Клиент» автоматически после сохранения технического задания,
  /// а в режиме «Проектировщик» — как «Сбросить к рекомендации».
  Future<void> applyAutoComposition(HouseProject project) async {
    final plan = CompositionPlanner.plan(project.brief);
    project.foundation = plan.foundation;
    project.walls = plan.walls;
    project.roof = plan.roof;
    if (plan.includesStaircase) {
      project.staircase = plan.staircase;
    }
    await saveProject(project);
  }

  /// Сгенерировать новую партию чертежей по текущему состоянию проекта.
  /// Старые чертежи остаются в коллекции, новые попадают в начало списка
  /// (за счёт сортировки по [Drawing.createdAt]).
  ///
  /// Если [autoFix] — `true` (по умолчанию), генератор молчаливо убирает
  /// мебель, блокирующую проходы (ширина < 0.9 м), чтобы устранить
  /// предупреждения о недостижимости комнат. Передайте `false`, если
  /// нужно увидеть исходные предупреждения без авто-коррекции (например,
  /// при отладке).
  ///
  /// v68: до этого по умолчанию был `false` — пользователь видел
  /// предупреждения и должен был жать «Исправить» вручную. Теперь
  /// rollback мебели делается автоматически при каждой регенерации;
  /// кнопка «Исправить» сохранена для backwards-compat.
  Future<void> regenerateDrawings(
    HouseProject project, {
    bool autoFix = true,
  }) async {
    final mode = _mode ?? UserMode.client;
    final batch = DrawingGenerator.generate(
      project: project,
      mode: mode,
      autoFix: autoFix,
    );
    project.drawings.addBatch(batch);
    await saveProject(project);
  }

  /// Сохранить ручную правку плана как новую версию чертежей.
  ///
  /// Берётся самая свежая партия чертежей, в ней целевой план
  /// (по идентификатору исходного [Drawing]) заменяется на отредактированный,
  /// остальные листы копируются как есть. Новая партия получает текущий
  /// timestamp и помечается флагом [Drawing.isManualEdit] — это видно на
  /// странице «Чертежи» как чип «ручная правка».
  Future<void> saveManualPlanEdit({
    required HouseProject project,
    required String sourceDrawingId,
    required FloorPlan editedPlan,
  }) async {
    final list = project.drawings.drawings;
    if (list.isEmpty) return;
    // Самая свежая партия — это все Drawings с одним и тем же createdAt
    // в начале списка после сортировки.
    final latestTs = list.first.createdAt;
    final batch = list.where((d) => d.createdAt == latestTs).toList();
    final now = DateTime.now();
    final newBatch = <Drawing>[];
    for (final d in batch) {
      if (d.id == sourceDrawingId) {
        newBatch.add(Drawing(
          id: _uuid.v4(),
          title: d.title,
          kind: d.kind,
          createdAt: now,
          payload: editedPlan.encode(),
          isManualEdit: true,
        ));
      } else {
        newBatch.add(d.copyWith(
          id: _uuid.v4(),
          createdAt: now,
        ));
      }
    }
    project.drawings.addBatch(newBatch);
    await saveProject(project);
  }

  Future<void> _persist() => _projects.saveAll(_projectList);

  static int _byUpdatedDesc(HouseProject a, HouseProject b) =>
      b.updatedAt.compareTo(a.updatedAt);
}
