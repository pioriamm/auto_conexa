import 'package:flutter/material.dart';

enum AppSection { fluxoCobranca, comissoes }

class NavigationViewModel extends ChangeNotifier {
  AppSection _current = AppSection.fluxoCobranca;

  AppSection get current => _current;

  void setSection(AppSection section) {
    if (_current == section) return;
    _current = section;
    notifyListeners();
  }
}
