import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// In-app Privacy Policy page.
///
/// Displays a scrollable, localized privacy policy that satisfies
/// Google Play's "News" category requirements for in-app contact
/// and data-handling disclosure.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacyPolicy),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
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
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Dondurma RSS Reader',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEnglish ? 'Privacy Policy' : 'Gizlilik Politikası',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isEnglish
                        ? 'Last updated: June 2026'
                        : 'Son güncelleme: Haziran 2026',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sections
            ..._buildSections(context, isEnglish),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context, bool isEnglish) {
    final theme = Theme.of(context);

    final sections = isEnglish
        ? [
            _SectionData(
              icon: Icons.info_outline,
              title: 'Introduction',
              content:
                  'Dondurma RSS Reader ("the App") is developed by DevOpen (Talha Aksoy & Eren Gün). '
                  'We are committed to protecting your privacy. This Privacy Policy explains how the App '
                  'handles your information.',
            ),
            _SectionData(
              icon: Icons.storage_outlined,
              title: 'Data Collection & Storage',
              content:
                  'The App stores all data locally on your device using Hive database. '
                  'We do NOT collect, transmit, or store any personal data on external servers.\n\n'
                  'Data stored locally includes:\n'
                  '• RSS feed subscriptions (URLs and names)\n'
                  '• Cached article content for offline reading\n'
                  '• Bookmarked articles\n'
                  '• App settings and preferences\n'
                  '• Search history',
            ),
            _SectionData(
              icon: Icons.cloud_off_outlined,
              title: 'No Server Communication',
              content:
                  'The App does not have its own backend server. All RSS feeds are fetched '
                  'directly from the original source websites. We do not act as an intermediary '
                  'and do not log, monitor, or store your reading activity.',
            ),
            _SectionData(
              icon: Icons.extension_outlined,
              title: 'Third-Party Services',
              content:
                  'The App uses the following third-party services:\n\n'
                  '• Google Fonts — for typography (Outfit font family)\n'
                  '• WebView — for displaying web content within the app\n'
                  '• Ad Blocker (adblocker_webview) — optional ad filtering in the built-in browser\n\n'
                  'These services may have their own privacy policies. We recommend reviewing them.',
            ),
            _SectionData(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              content:
                  'The App may send local notifications for new articles. These notifications '
                  'are generated entirely on your device and do not involve any external push '
                  'notification service. You can disable notifications at any time in Settings.',
            ),
            _SectionData(
              icon: Icons.security_outlined,
              title: 'Data Security',
              content:
                  'Since all data is stored locally on your device, the security of your data '
                  'depends on your device\'s security. We recommend using device-level security '
                  'measures such as screen lock and encryption.',
            ),
            _SectionData(
              icon: Icons.child_care_outlined,
              title: 'Children\'s Privacy',
              content:
                  'The App is not directed at children under the age of 13. We do not knowingly '
                  'collect any personal information from children.',
            ),
            _SectionData(
              icon: Icons.update_outlined,
              title: 'Changes to This Policy',
              content:
                  'We may update this Privacy Policy from time to time. Any changes will be '
                  'reflected in the App and the updated date will be changed accordingly.',
            ),
            _SectionData(
              icon: Icons.email_outlined,
              title: 'Contact Us',
              content:
                  'If you have any questions about this Privacy Policy, please contact us:\n\n'
                  '📧 Email: info@devopen.io\n'
                  '🌐 Website: https://github.com/DevOpen-io',
            ),
          ]
        : [
            _SectionData(
              icon: Icons.info_outline,
              title: 'Giriş',
              content:
                  'Dondurma RSS Reader ("Uygulama"), DevOpen (Talha Aksoy & Eren Gün) tarafından '
                  'geliştirilmektedir. Gizliliğinizi korumaya kararlıyız. Bu Gizlilik Politikası, '
                  'Uygulamanın bilgilerinizi nasıl işlediğini açıklar.',
            ),
            _SectionData(
              icon: Icons.storage_outlined,
              title: 'Veri Toplama ve Depolama',
              content:
                  'Uygulama, tüm verileri Hive veritabanı kullanarak cihazınızda yerel olarak depolar. '
                  'Herhangi bir kişisel veriyi harici sunucularda TOPLAMIYORUZ, AKTARMIYORUZ veya SAKLAMIYORUZ.\n\n'
                  'Yerel olarak depolanan veriler:\n'
                  '• RSS kaynak abonelikleri (URL\'ler ve adlar)\n'
                  '• Çevrimdışı okuma için önbelleğe alınmış makale içerikleri\n'
                  '• Yer işaretli makaleler\n'
                  '• Uygulama ayarları ve tercihleri\n'
                  '• Arama geçmişi',
            ),
            _SectionData(
              icon: Icons.cloud_off_outlined,
              title: 'Sunucu İletişimi Yok',
              content:
                  'Uygulamanın kendi arka plan sunucusu yoktur. Tüm RSS akışları doğrudan orijinal '
                  'kaynak web sitelerinden alınır. Aracı olarak hareket etmiyoruz ve okuma '
                  'aktivitenizi kaydetmiyor, izlemiyor veya saklamıyoruz.',
            ),
            _SectionData(
              icon: Icons.extension_outlined,
              title: 'Üçüncü Taraf Hizmetler',
              content:
                  'Uygulama aşağıdaki üçüncü taraf hizmetleri kullanır:\n\n'
                  '• Google Fonts — tipografi için (Outfit yazı tipi ailesi)\n'
                  '• WebView — uygulama içinde web içeriği görüntülemek için\n'
                  '• Reklam Engelleyici (adblocker_webview) — dahili tarayıcıda isteğe bağlı reklam filtreleme\n\n'
                  'Bu hizmetlerin kendi gizlilik politikaları olabilir. Bunları incelemenizi öneririz.',
            ),
            _SectionData(
              icon: Icons.notifications_outlined,
              title: 'Bildirimler',
              content:
                  'Uygulama, yeni makaleler için yerel bildirimler gönderebilir. Bu bildirimler '
                  'tamamen cihazınızda oluşturulur ve herhangi bir harici push bildirim hizmeti '
                  'içermez. Bildirimleri istediğiniz zaman Ayarlar\'dan devre dışı bırakabilirsiniz.',
            ),
            _SectionData(
              icon: Icons.security_outlined,
              title: 'Veri Güvenliği',
              content:
                  'Tüm veriler cihazınızda yerel olarak depolandığından, verilerinizin güvenliği '
                  'cihazınızın güvenliğine bağlıdır. Ekran kilidi ve şifreleme gibi cihaz düzeyinde '
                  'güvenlik önlemleri kullanmanızı öneririz.',
            ),
            _SectionData(
              icon: Icons.child_care_outlined,
              title: 'Çocukların Gizliliği',
              content:
                  'Uygulama, 13 yaşın altındaki çocuklara yönelik değildir. Çocuklardan bilerek '
                  'herhangi bir kişisel bilgi toplamıyoruz.',
            ),
            _SectionData(
              icon: Icons.update_outlined,
              title: 'Bu Politikadaki Değişiklikler',
              content:
                  'Bu Gizlilik Politikasını zaman zaman güncelleyebiliriz. Herhangi bir değişiklik '
                  'Uygulamaya yansıtılacak ve güncelleme tarihi buna göre değiştirilecektir.',
            ),
            _SectionData(
              icon: Icons.email_outlined,
              title: 'Bize Ulaşın',
              content:
                  'Bu Gizlilik Politikası hakkında sorularınız varsa lütfen bizimle iletişime geçin:\n\n'
                  '📧 E-posta: info@devopen.io\n'
                  '🌐 Web sitesi: https://github.com/DevOpen-io',
            ),
          ];

    return sections.map((section) {
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
              Row(
                children: [
                  Icon(
                    section.icon,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                section.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _SectionData {
  final IconData icon;
  final String title;
  final String content;

  const _SectionData({
    required this.icon,
    required this.title,
    required this.content,
  });
}
