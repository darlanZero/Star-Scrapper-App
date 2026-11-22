import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/locale/locale_provider.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('LocaleProvider defaults to system and persists locale choices',
      () async {
    final provider = LocaleProvider();
    expect(provider.locale, isNull);
    expect(provider.localeTag, 'system');

    await provider.setLocaleTag('pt_BR');
    expect(provider.locale, const Locale('pt', 'BR'));
    expect(provider.localeTag, 'pt_BR');

    await provider.setLocaleTag('es');
    expect(provider.locale, const Locale('es'));
    expect(provider.localeTag, 'es');

    await provider.setLocaleTag('en');
    expect(provider.locale, const Locale('en'));
    expect(provider.localeTag, 'en');

    await provider.setLocaleTag('system');
    expect(provider.locale, isNull);
    expect(provider.localeTag, 'system');
  });

  testWidgets('AppLocalizations resolves en, pt_BR, and es loadingMore',
      (tester) async {
    Future<String> pumpForLocale(Locale locale) async {
      late String resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              resolved = context.l10n.loadingMore;
              return Text(resolved);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return resolved;
    }

    expect(await pumpForLocale(const Locale('en')), 'Loading more...');
    expect(
      await pumpForLocale(const Locale('pt', 'BR')),
      'Carregando mais...',
    );
    expect(await pumpForLocale(const Locale('es')), 'Cargando más...');
  });
}
