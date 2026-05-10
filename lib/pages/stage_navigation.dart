import 'package:flutter/material.dart';

/// Утилита для прыжка между этапами проекта без накопления промежуточных
/// экранов в стеке навигации.
///
/// Каждый этап (визард брифа, planning-страница, фундамент, кровля) после
/// сохранения данных может попросить «перейти к следующему этапу». Если
/// мы просто сделаем `pushReplacement(NextStage)`, в стеке остаются все
/// промежуточные экраны (например, FoundationTypePage и FoundationDevicePage
/// между ProjectDetails и RoofPage). По нажатию back пользователь
/// возвращался бы не на главную, а в середину предыдущего визарда.
///
/// Решение: помечаем `ProjectDetailsPage` именованным маршрутом
/// `'project-details'` и делаем `popUntil(name == 'project-details')`,
/// после чего `push` нового этапа. Стек становится:
///   `[Initial → ProjectsOfType → ProjectDetails → NextStage]`.
/// Назад с NextStage — на ProjectDetails. Это совпадает с обычным
/// поведением, как если бы пользователь сам кликнул карточку этапа.
class StageNavigation {
  StageNavigation._();

  /// Имя маршрута для [ProjectDetailsPage]. Используется в [popUntil].
  static const String projectDetailsRouteName = 'project-details';

  /// Сбрасывает стек до [ProjectDetailsPage] и кладёт сверху [page].
  ///
  /// Если по какой-то причине маршрут с именем `project-details` не
  /// найден (например, сценарий внешнего deep-link), просто
  /// `pushReplacement` — лучше иметь пусть и накопленный стек, чем
  /// схлопнуть всё до корневого маршрута.
  static void jumpToStage(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    bool foundProjectDetails = false;
    navigator.popUntil((route) {
      if (route.settings.name == projectDetailsRouteName) {
        foundProjectDetails = true;
        return true;
      }
      return route.isFirst;
    });
    if (foundProjectDetails) {
      navigator.push(MaterialPageRoute(builder: (_) => page));
    } else {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => page));
    }
  }
}
