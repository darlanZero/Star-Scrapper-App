import 'package:flutter/widgets.dart';
import 'package:star_scrapper_app/l10n/app_localizations.dart';
import 'package:star_scrapper_app/l10n/app_localizations_en.dart';

export 'package:star_scrapper_app/l10n/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsEn();
}
