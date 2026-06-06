import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// In-app Terms of Service page.
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.termsOfService), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, isEn),
            const SizedBox(height: 24),
            ..._sections(isEn).map((s) => _card(theme, s)),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, bool isEn) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.description_outlined, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Dondurma RSS Reader',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(isEn ? 'Terms of Service' : 'Kullanım Koşulları',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Text(isEn ? 'Last updated: June 2026' : 'Son güncelleme: Haziran 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, _S s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(s.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(s.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.6)),
          ],
        ),
      ),
    );
  }

  List<_S> _sections(bool isEn) => isEn ? _enSections : _trSections;

  static const _enSections = [
    _S(Icons.check_circle_outline, '1. Acceptance of Terms',
        'By downloading, installing, or using Dondurma RSS Reader ("the App"), you agree to be bound by these Terms of Service. If you do not agree, please do not use the App.'),
    _S(Icons.article_outlined, '2. Description of Service',
        'Dondurma RSS Reader is a free, open-source RSS/Atom feed reader. The App allows you to subscribe to and read RSS feeds from various websites. The App does not produce, publish, or curate any news content.'),
    _S(Icons.rss_feed_outlined, '3. Third-Party Content',
        'The App displays content from third-party RSS feeds. We are not responsible for the accuracy, completeness, or reliability of any third-party content. The content belongs to the respective publishers.'),
    _S(Icons.person_outline, '4. User Responsibilities',
        'You are responsible for:\n• The RSS feeds you choose to subscribe to\n• Ensuring your use complies with applicable laws\n• Maintaining the security of your device\n• Any data you export or share from the App'),
    _S(Icons.copyright_outlined, '5. Intellectual Property',
        'The App is open-source software developed by DevOpen. The source code is available on GitHub. Content displayed in RSS feeds is owned by the respective content creators and publishers.'),
    _S(Icons.warning_amber_outlined, '6. Disclaimer of Warranties',
        'The App is provided "as is" without warranties of any kind. We do not guarantee that the App will be error-free, uninterrupted, or that all RSS feeds will be accessible at all times.'),
    _S(Icons.gavel_outlined, '7. Limitation of Liability',
        'DevOpen and its developers shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of the App.'),
    _S(Icons.update_outlined, '8. Changes to Terms',
        'We reserve the right to modify these Terms at any time. Continued use of the App after changes constitutes acceptance of the new terms.'),
    _S(Icons.email_outlined, '9. Contact',
        'For questions about these Terms of Service:\n\n📧 Email: info@devopen.io\n🌐 Website: https://github.com/DevOpen-io'),
  ];

  static const _trSections = [
    _S(Icons.check_circle_outline, '1. Koşulların Kabulü',
        'Dondurma RSS Reader ("Uygulama") uygulamasını indirerek, yükleyerek veya kullanarak bu Kullanım Koşullarına bağlı olmayı kabul edersiniz. Kabul etmiyorsanız lütfen Uygulamayı kullanmayın.'),
    _S(Icons.article_outlined, '2. Hizmet Açıklaması',
        'Dondurma RSS Reader, ücretsiz ve açık kaynaklı bir RSS/Atom akış okuyucusudur. Uygulama, çeşitli web sitelerinden RSS akışlarına abone olmanızı ve bunları okumanızı sağlar. Uygulama herhangi bir haber içeriği üretmez veya yayınlamaz.'),
    _S(Icons.rss_feed_outlined, '3. Üçüncü Taraf İçerik',
        'Uygulama, üçüncü taraf RSS akışlarından içerik görüntüler. Üçüncü taraf içeriğinin doğruluğundan veya güvenilirliğinden sorumlu değiliz. İçerik ilgili yayıncılara aittir.'),
    _S(Icons.person_outline, '4. Kullanıcı Sorumlulukları',
        'Aşağıdakilerden siz sorumlusunuz:\n• Abone olmayı seçtiğiniz RSS akışları\n• Kullanımınızın geçerli yasalara uygunluğu\n• Cihazınızın güvenliği\n• Uygulamadan dışa aktardığınız veya paylaştığınız veriler'),
    _S(Icons.copyright_outlined, '5. Fikri Mülkiyet',
        'Uygulama, DevOpen tarafından geliştirilen açık kaynaklı bir yazılımdır. Kaynak kodu GitHub\'da mevcuttur. RSS akışlarındaki içerik ilgili içerik oluşturucularına aittir.'),
    _S(Icons.warning_amber_outlined, '6. Garanti Reddi',
        'Uygulama herhangi bir garanti olmaksızın "olduğu gibi" sunulmaktadır. Uygulamanın hatasız veya kesintisiz olacağını garanti etmiyoruz.'),
    _S(Icons.gavel_outlined, '7. Sorumluluk Sınırlaması',
        'DevOpen ve geliştiricileri, Uygulamayı kullanımınızdan kaynaklanan dolaylı veya sonuç olarak ortaya çıkan zararlardan sorumlu tutulamaz.'),
    _S(Icons.update_outlined, '8. Koşullardaki Değişiklikler',
        'Bu Kullanım Koşullarını herhangi bir zamanda değiştirme hakkını saklı tutarız. Değişikliklerden sonra kullanmaya devam etmeniz yeni koşulları kabul ettiğiniz anlamına gelir.'),
    _S(Icons.email_outlined, '9. İletişim',
        'Bu Kullanım Koşulları hakkında sorularınız için:\n\n📧 E-posta: info@devopen.io\n🌐 Web sitesi: https://github.com/DevOpen-io'),
  ];
}

class _S {
  final IconData icon;
  final String title;
  final String content;
  const _S(this.icon, this.title, this.content);
}
