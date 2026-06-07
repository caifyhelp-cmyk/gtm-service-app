import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const GTMServiceApp());
}

// ── 앱 버전 (pubspec.yaml의 version과 동일하게 유지)
const _appVersion = '1.0.1';
const _githubRepo = 'caifyhelp-cmyk/gtm-service-app';

// ── 컬러 상수
const kPrimary = Color(0xFF2563EB);
const kSuccess = Color(0xFF16A34A);
const kError = Color(0xFFDC2626);
const kBg = Color(0xFFF8FAFC);

// ── GoogleSignIn 인스턴스 (기본 로그인용 — 민감 스코프는 requestScopes로 별도 요청)
final _googleSignIn = GoogleSignIn(scopes: ['email']);

// ── GTM + GA4 접근에 필요한 민감 스코프
const _requiredScopes = [
  'https://www.googleapis.com/auth/tagmanager.readonly',
  'https://www.googleapis.com/auth/tagmanager.edit.containers',
  'https://www.googleapis.com/auth/tagmanager.publish',
  'https://www.googleapis.com/auth/analytics.readonly',
  'https://www.googleapis.com/auth/analytics.manage.users',
  'https://www.googleapis.com/auth/analytics.edit',
];

// ── 유효 서비스 코드 목록
const _validCodes = ['CAIFY001', 'CAIFY002', 'CAIFY003', 'CAIFY-TEST'];

// ── 세팅 데이터 모델
class SetupData {
  String serviceCode;
  String websiteUrl;
  String projectName;
  String platform;

  SetupData({
    this.serviceCode = '',
    this.websiteUrl = '',
    this.projectName = '',
    this.platform = '카페24',
  });
}

// ── 진행 단계 상태
enum StepStatus { waiting, running, done, error }

class ProgressStep {
  final String label;
  StepStatus status;
  String? errorMessage;

  ProgressStep(this.label, {this.status = StepStatus.waiting});
}

// ════════════════════════════════════════════
// 앱
// ════════════════════════════════════════════
class GTMServiceApp extends StatelessWidget {
  const GTMServiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GTM+GA4 자동 세팅',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        useMaterial3: true,
      ),
      home: WelcomePage(setupData: SetupData()),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ════════════════════════════════════════════
// 자동 업데이트
// ════════════════════════════════════════════

bool _isNewerVersion(String latest, String current) {
  final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    final lv = i < l.length ? l[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

Future<void> checkForUpdate(BuildContext context) async {
  try {
    final res = await http.get(
      Uri.parse(
          'https://api.github.com/repos/$_githubRepo/releases/latest'),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = ((data['tag_name'] as String?) ?? '').replaceFirst('v', '');
    if (!_isNewerVersion(tag, _appVersion)) return;

    final assets = data['assets'] as List? ?? [];
    final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => {},
        );
    final downloadUrl = apkAsset['browser_download_url'] as String?;
    if (downloadUrl == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(version: tag, downloadUrl: downloadUrl),
    );
  } catch (_) {}
}

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String downloadUrl;
  const _UpdateDialog({required this.version, required this.downloadUrl});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gtm-service-update.apk');

      final req = http.Request('GET', Uri.parse(widget.downloadUrl));
      final streamedRes = await req.send();
      final total = streamedRes.contentLength ?? 0;
      int received = 0;
      final sink = file.openWrite();

      await for (final chunk in streamedRes.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          setState(() => _progress = received / total);
        }
      }
      await sink.close();
      setState(() => _progress = 1.0);

      await OpenFile.open(file.path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = '다운로드 실패: $e';
        _downloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.system_update, color: kPrimary),
          SizedBox(width: 10),
          Text('업데이트 알림', style: TextStyle(fontSize: 17)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('새 버전 v${widget.version}이 출시되었습니다.\n지금 업데이트하시겠습니까?',
              style: const TextStyle(fontSize: 14)),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: const Color(0xFFE2E8F0),
              color: kPrimary,
            ),
            const SizedBox(height: 8),
            Text(
              _progress == null
                  ? '준비 중...'
                  : _progress! < 1.0
                      ? '다운로드 중... ${(_progress! * 100).toStringAsFixed(0)}%'
                      : '설치 파일 열기...',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
          ],
        ],
      ),
      actions: _downloading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('나중에',
                    style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: _download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('업데이트'),
              ),
            ],
    );
  }
}

// ════════════════════════════════════════════
// 1. WelcomePage
// ════════════════════════════════════════════
class WelcomePage extends StatefulWidget {
  final SetupData setupData;
  const WelcomePage({super.key, required this.setupData});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _codeCtrl = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForUpdate(context);
    });
  }

  void _confirm() {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (_validCodes.contains(code)) {
      widget.setupData.serviceCode = code;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SetupFormPage(setupData: widget.setupData),
        ),
      );
    } else {
      setState(() => _errorText = '유효하지 않은 코드입니다. 다시 확인해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고/타이틀
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.settings_suggest,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                const Text(
                  'GTM+GA4 자동 세팅',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'GTM 컨테이너와 GA4 속성을\n자동으로 생성·연동해드립니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 48),

                // 코드 입력 카드
                _AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '서비스 코드 입력',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '결제 후 받으신 코드를 입력해주세요.',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'CAIFY001',
                          errorText: _errorText,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: kPrimary, width: 2),
                          ),
                          prefixIcon:
                              const Icon(Icons.vpn_key_outlined),
                        ),
                        onSubmitted: (_) => _confirm(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('확인',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// 2. SetupFormPage
// ════════════════════════════════════════════
class SetupFormPage extends StatefulWidget {
  final SetupData setupData;
  const SetupFormPage({super.key, required this.setupData});

  @override
  State<SetupFormPage> createState() => _SetupFormPageState();
}

class _SetupFormPageState extends State<SetupFormPage> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _platform = '카페24';

  final _platforms = ['카페24', '고도몰', '워드프레스', '직접개발'];

  void _next() {
    if (_formKey.currentState!.validate()) {
      widget.setupData.websiteUrl = _urlCtrl.text.trim();
      widget.setupData.projectName = _nameCtrl.text.trim();
      widget.setupData.platform = _platform;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LoginPage(setupData: widget.setupData),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AppBar(title: '세팅 정보 입력', step: '2/5'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepHeader(
                icon: Icons.edit_note,
                title: '기본 정보를 입력해주세요',
                subtitle: 'GTM 컨테이너와 GA4 속성 생성에 사용됩니다.',
              ),
              const SizedBox(height: 24),

              _AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 웹사이트 URL
                    _FieldLabel('웹사이트 URL', required: true),
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: _inputDeco(
                          hint: 'https://example.com',
                          icon: Icons.language),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '웹사이트 URL을 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // 프로젝트명
                    _FieldLabel('프로젝트/사업체 이름', required: true),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _inputDeco(
                          hint: '내 쇼핑몰', icon: Icons.business),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '프로젝트 이름을 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // 플랫폼 선택
                    _FieldLabel('플랫폼', required: true),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _platforms.map((p) {
                        final selected = _platform == p;
                        return ChoiceChip(
                          label: Text(p),
                          selected: selected,
                          selectedColor: kPrimary.withOpacity(0.15),
                          labelStyle: TextStyle(
                            color: selected ? kPrimary : const Color(0xFF475569),
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (_) =>
                              setState(() => _platform = p),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('다음: Google 로그인',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// 3. LoginPage
// ════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  final SetupData setupData;
  const LoginPage({super.key, required this.setupData});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1단계: 계정 선택 팝업
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() {
          _loading = false;
          _error = '로그인이 취소되었습니다.';
        });
        return;
      }

      // 2단계: GTM/GA4 권한 동의 팝업 (다른 앱처럼 별도 팝업으로 표시)
      final granted = await _googleSignIn.requestScopes(_requiredScopes);
      if (!granted) {
        await _googleSignIn.signOut();
        setState(() {
          _loading = false;
          _error = 'GTM/GA4 접근 권한이 필요합니다. 모든 권한을 허용해주세요.';
        });
        return;
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) {
        setState(() {
          _loading = false;
          _error = '액세스 토큰을 가져올 수 없습니다.';
        });
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProgressPage(
            setupData: widget.setupData,
            token: token,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '로그인 오류: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AppBar(title: 'Google 로그인', step: '3/5'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _StepHeader(
              icon: Icons.login,
              title: 'Google 계정으로 로그인',
              subtitle:
                  '아래 버튼으로 Google 계정에 로그인하면, GTM 컨테이너와 GA4 속성이 자동으로 생성됩니다.',
            ),
            const SizedBox(height: 24),

            // 권한 안내 카드
            _AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '요청할 권한 안내',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  _PermItem(
                    icon: Icons.local_offer,
                    color: kPrimary,
                    title: 'GTM 편집 권한',
                    desc: '컨테이너 생성, 태그/트리거 설정, 게시',
                  ),
                  const SizedBox(height: 8),
                  _PermItem(
                    icon: Icons.bar_chart,
                    color: kSuccess,
                    title: 'GA4 편집 권한',
                    desc: '속성 생성, 데이터 스트림 설정',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 세팅 요약 카드
            _AppCard(
              color: const Color(0xFFEFF6FF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('입력한 정보 확인',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kPrimary,
                          fontSize: 14)),
                  const SizedBox(height: 10),
                  _InfoRow('URL', widget.setupData.websiteUrl),
                  _InfoRow('프로젝트명', widget.setupData.projectName),
                  _InfoRow('플랫폼', widget.setupData.platform),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: kError, fontSize: 13)),
              ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Icon(Icons.login),
                label: Text(
                  _loading ? '로그인 중...' : 'Google로 로그인 후 자동 세팅 시작',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// 4. ProgressPage
// ════════════════════════════════════════════
class ProgressPage extends StatefulWidget {
  final SetupData setupData;
  final String token;

  const ProgressPage({
    super.key,
    required this.setupData,
    required this.token,
  });

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  late List<ProgressStep> _steps;

  // 수집된 결과값
  String? _gtmAccountId;
  String? _gtmContainerId;
  String? _gtmPublicId;
  String? _ga4PropertyId;
  String? _measurementId;
  String? _workspaceId;
  String? _gtmVersionId;

  bool _finished = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _steps = [
      ProgressStep('Google 인증 완료'),
      ProgressStep('GTM 계정 확인'),
      ProgressStep('GTM 컨테이너 생성'),
      ProgressStep('GA4 속성 생성'),
      ProgressStep('GA4 웹 데이터 스트림 생성'),
      ProgressStep('GTM-GA4 연동 태그 생성'),
      ProgressStep('GTM 게시(Publish)'),
      ProgressStep('완료'),
    ];
    // 화면이 그려진 후 자동 실행
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  void _setStep(int i, StepStatus s, {String? err}) {
    setState(() {
      _steps[i].status = s;
      _steps[i].errorMessage = err;
    });
  }

  Future<Map<String, dynamic>> _apiGet(String url) async {
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('GET $url → ${res.statusCode}\n${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _apiPost(
      String url, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('POST $url → ${res.statusCode}\n${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _runAll() async {
    try {
      // ── 단계 1: Google 인증 완료 (이미 토큰 있음)
      _setStep(0, StepStatus.running);
      await Future.delayed(const Duration(milliseconds: 500));
      _setStep(0, StepStatus.done);

      // ── 단계 2: GTM 계정 확인
      _setStep(1, StepStatus.running);
      final gtmAccountsData = await _apiGet(
          'https://www.googleapis.com/tagmanager/v2/accounts');
      final accounts =
          (gtmAccountsData['account'] as List? ?? []);
      if (accounts.isEmpty) {
        _setStep(1, StepStatus.error,
            err: 'GTM 계정이 없습니다. tagmanager.google.com 에서 계정을 먼저 생성해주세요.');
        setState(() => _hasError = true);
        return;
      }
      _gtmAccountId = accounts[0]['accountId']?.toString() ??
          (accounts[0]['name'] as String?)?.split('/').last;
      _setStep(1, StepStatus.done);

      // ── 단계 3: GTM 컨테이너 생성
      _setStep(2, StepStatus.running);
      final containerName =
          '${widget.setupData.projectName} - ${widget.setupData.platform}';
      final containerData = await _apiPost(
        'https://www.googleapis.com/tagmanager/v2/accounts/$_gtmAccountId/containers',
        {
          'name': containerName,
          'usageContext': ['web'],
        },
      );
      _gtmContainerId =
          containerData['containerId']?.toString() ??
              (containerData['name'] as String?)?.split('/').last;
      _gtmPublicId = containerData['publicId']?.toString();
      _setStep(2, StepStatus.done);

      // ── 단계 4: GA4 속성 생성
      _setStep(3, StepStatus.running);
      final ga4AccountsData = await _apiGet(
          'https://analyticsadmin.googleapis.com/v1beta/accounts');
      final ga4Accounts =
          (ga4AccountsData['accounts'] as List? ?? []);
      if (ga4Accounts.isEmpty) {
        _setStep(3, StepStatus.error,
            err: 'GA4 계정이 없습니다. analytics.google.com 에서 계정을 먼저 생성해주세요.');
        setState(() => _hasError = true);
        return;
      }
      final ga4AccountName =
          ga4Accounts[0]['name']?.toString() ?? '';
      final ga4AccountId = ga4AccountName.split('/').last;

      final propertyData = await _apiPost(
        'https://analyticsadmin.googleapis.com/v1beta/properties',
        {
          'displayName': widget.setupData.projectName,
          'timeZone': 'Asia/Seoul',
          'currencyCode': 'KRW',
          'industryCategory': 'SHOPPING',
          'parent': 'accounts/$ga4AccountId',
        },
      );
      _ga4PropertyId = propertyData['name']?.toString();
      _setStep(3, StepStatus.done);

      // ── 단계 5: GA4 웹 데이터 스트림 생성
      _setStep(4, StepStatus.running);
      final streamData = await _apiPost(
        'https://analyticsadmin.googleapis.com/v1beta/$_ga4PropertyId/dataStreams',
        {
          'type': 'WEB_DATA_STREAM',
          'displayName': widget.setupData.websiteUrl,
          'webStreamData': {
            'defaultUri': widget.setupData.websiteUrl,
          },
        },
      );
      _measurementId = streamData['webStreamData']?['measurementId']
              ?.toString() ??
          streamData['measurementId']?.toString();
      _setStep(4, StepStatus.done);

      // ── 단계 6: GTM 워크스페이스 조회 + 태그/트리거 생성
      _setStep(5, StepStatus.running);
      final wsData = await _apiGet(
        'https://www.googleapis.com/tagmanager/v2'
        '/accounts/$_gtmAccountId/containers/$_gtmContainerId/workspaces',
      );
      final workspaces = (wsData['workspace'] as List? ?? []);
      if (workspaces.isEmpty) {
        _setStep(5, StepStatus.error,
            err: 'GTM 워크스페이스를 찾을 수 없습니다.');
        setState(() => _hasError = true);
        return;
      }
      _workspaceId = workspaces[0]['workspaceId']?.toString() ??
          (workspaces[0]['name'] as String?)?.split('/').last;

      final wsBase =
          'https://www.googleapis.com/tagmanager/v2/accounts/$_gtmAccountId'
          '/containers/$_gtmContainerId/workspaces/$_workspaceId';

      // 트리거 생성
      final triggerData = await _apiPost(
        '$wsBase/triggers',
        {'name': 'All Pages', 'type': 'PAGEVIEW'},
      );
      final triggerId = triggerData['triggerId']?.toString() ??
          (triggerData['name'] as String?)?.split('/').last ??
          '';

      // 태그 생성 (GA4 Configuration)
      await _apiPost(
        '$wsBase/tags',
        {
          'name': 'GA4 - Configuration',
          'type': 'googtag',
          'parameter': [
            {
              'type': 'TEMPLATE',
              'key': 'tagId',
              'value': _measurementId ?? '',
            }
          ],
          'firingTriggerId': [triggerId],
        },
      );
      _setStep(5, StepStatus.done);

      // ── 단계 7: GTM 버전 생성 + 퍼블리시
      _setStep(6, StepStatus.running);
      final versionData = await _apiPost(
        '$wsBase:create_version',
        {'name': 'v1 - 자동 세팅', 'notes': 'GA4 자동 연동'},
      );
      _gtmVersionId = versionData['containerVersion']?['containerVersionId']
              ?.toString() ??
          versionData['containerVersionId']?.toString();

      await _apiPost(
        'https://www.googleapis.com/tagmanager/v2'
        '/accounts/$_gtmAccountId/containers/$_gtmContainerId'
        '/versions/$_gtmVersionId:publish',
        {},
      );
      _setStep(6, StepStatus.done);

      // ── 단계 8: 완료
      _setStep(7, StepStatus.done);
      setState(() => _finished = true);

      // CompletePage로 이동
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompletePage(
            setupData: widget.setupData,
            gtmPublicId: _gtmPublicId ?? 'GTM-XXXXXX',
            measurementId: _measurementId ?? 'G-XXXXXXXXXX',
          ),
        ),
      );
    } catch (e) {
      // 현재 running 상태인 단계를 error로
      for (int i = 0; i < _steps.length; i++) {
        if (_steps[i].status == StepStatus.running) {
          _setStep(i, StepStatus.error, err: e.toString());
          break;
        }
      }
      setState(() => _hasError = true);
    }
  }

  void _retry() {
    // 상태 초기화 후 재시도
    setState(() {
      for (final s in _steps) {
        s.status = StepStatus.waiting;
        s.errorMessage = null;
      }
      _hasError = false;
      _finished = false;
      _gtmAccountId = null;
      _gtmContainerId = null;
      _gtmPublicId = null;
      _ga4PropertyId = null;
      _measurementId = null;
      _workspaceId = null;
      _gtmVersionId = null;
    });
    _runAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AppBar(title: '자동 세팅 진행 중', step: '4/5'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _StepHeader(
              icon: Icons.autorenew,
              title: 'GTM + GA4 자동 세팅 중',
              subtitle: '각 단계를 순서대로 처리하고 있습니다. 잠시 기다려주세요.',
            ),
            const SizedBox(height: 24),

            _AppCard(
              child: Column(
                children: List.generate(_steps.length, (i) {
                  return _ProgressStepTile(
                    step: _steps[i],
                    isLast: i == _steps.length - 1,
                  );
                }),
              ),
            ),

            if (_hasError) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kError,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 단계 타일 위젯
class _ProgressStepTile extends StatelessWidget {
  final ProgressStep step;
  final bool isLast;

  const _ProgressStepTile({required this.step, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    Widget icon;
    switch (step.status) {
      case StepStatus.waiting:
        icon = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
          ),
        );
        break;
      case StepStatus.running:
        icon = const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: kPrimary),
        );
        break;
      case StepStatus.done:
        icon = const Icon(Icons.check_circle, color: kSuccess, size: 24);
        break;
      case StepStatus.error:
        icon = const Icon(Icons.cancel, color: kError, size: 24);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              icon,
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: const Color(0xFFE2E8F0),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: step.status == StepStatus.done
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: step.status == StepStatus.waiting
                          ? const Color(0xFF94A3B8)
                          : step.status == StepStatus.error
                              ? kError
                              : const Color(0xFF1E293B),
                    ),
                  ),
                  if (step.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      step.errorMessage!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: kError),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
// 5. CompletePage
// ════════════════════════════════════════════
class CompletePage extends StatelessWidget {
  final SetupData setupData;
  final String gtmPublicId;
  final String measurementId;

  const CompletePage({
    super.key,
    required this.setupData,
    required this.gtmPublicId,
    required this.measurementId,
  });

  String get _gtmHeadSnippet => '''<!-- Google Tag Manager -->
<script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
})(window,document,'script','dataLayer','$gtmPublicId');</script>
<!-- End Google Tag Manager -->''';

  String get _gtmBodySnippet => '''<!-- Google Tag Manager (noscript) -->
<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=$gtmPublicId"
height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>
<!-- End Google Tag Manager (noscript) -->''';

  // 플랫폼별 설치 위치 안내
  Map<String, String> get _installGuide => {
    '카페24': '카페24 관리자 → 디자인 → HTML 편집\n'
        '• [헤더 코드] head 태그 닫기(<\/head>) 바로 위에 GTM head 코드 삽입\n'
        '• [바디 코드] body 태그 열기(<body>) 바로 아래에 GTM body 코드 삽입\n'
        '저장 후 사이트에서 F12 → Elements에서 GTM 스크립트 확인',
    '고도몰': '고도몰 관리자 → 디자인 → PC 화면설정 → 레이아웃 관리\n'
        '• [헤더 코드] 공통 헤더 HTML에서 </head> 바로 위에 삽입\n'
        '• [바디 코드] 공통 헤더 HTML의 <body> 바로 다음 줄에 삽입\n'
        '저장 후 미리보기로 반영 확인',
    '워드프레스': '방법 1 (플러그인): Insert Headers and Footers 설치\n'
        '• Settings → Insert Headers and Footers\n'
        '• Header 영역: GTM head 코드 붙여넣기\n'
        '• Body 영역: GTM body 코드 붙여넣기\n\n'
        '방법 2 (직접): 외모 → 테마 편집기 → header.php\n'
        '• </head> 위에 GTM head 코드, <body> 아래에 GTM body 코드 삽입',
    '직접개발': '모든 페이지의 HTML에 아래 코드를 삽입하세요.\n'
        '• GTM head 코드 → <head> 태그 내부 최상단\n'
        '• GTM body 코드 → <body> 태그 바로 다음\n'
        'SPA(React/Vue)는 index.html 또는 _document.js에 삽입',
  };

  // 플랫폼별 전화번호 클릭 dataLayer 코드
  String get _dataLayerCode {
    const base = "window.dataLayer = window.dataLayer || [];\n"
        "dataLayer.push({\n"
        "  'event': 'tel_click',\n"
        "  'event_category': '전화문의',\n"
        "  'event_label': '전화번호클릭'\n"
        "});";

    switch (setupData.platform) {
      case '카페24':
        return '<!-- 카페24: 전화번호 링크(tel:)에 onclick 추가 -->\n'
            '<a href="tel:010-0000-0000"\n'
            '   onclick="$base">\n'
            '  전화하기\n'
            '</a>';
      case '고도몰':
        return '<!-- 고도몰: 전화번호 링크에 onclick 추가 -->\n'
            '<a href="tel:010-0000-0000"\n'
            '   onclick="$base">\n'
            '  전화하기\n'
            '</a>';
      case '워드프레스':
        return '<!-- WordPress: functions.php 또는 커스텀 JS 파일에 추가 -->\n'
            'jQuery(document).ready(function(\$) {\n'
            '  \$("a[href^=\'tel:\']").on("click", function() {\n'
            '    $base\n'
            '  });\n'
            '});';
      default:
        return '// 전화번호 링크 클릭 이벤트\n'
            'document.querySelectorAll("a[href^=\'tel:\']")\n'
            '  .forEach(el => el.addEventListener("click", () => {\n'
            '    $base\n'
            '  }));';
    }
  }

  void _copy(BuildContext ctx, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('$label 복사됨'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AppBar(title: '세팅 완료', step: '5/5'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 완료 헤더
            Center(
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kSuccess.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle,
                        color: kSuccess, size: 44),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'GTM+GA4 세팅 완료!',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${setupData.projectName} 프로젝트의 GTM 컨테이너와\nGA4 속성이 성공적으로 생성·연동되었습니다.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // GA4 측정 ID
            _SectionTitle('GA4 측정 ID'),
            const SizedBox(height: 8),
            _AppCard(
              child: Row(
                children: [
                  const Icon(Icons.bar_chart, color: kSuccess),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      measurementId,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kSuccess),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () =>
                        _copy(context, measurementId, 'GA4 측정 ID'),
                    tooltip: '복사',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // GTM Head 코드
            _SectionTitle('GTM 코드 — <head> 태그 안에 삽입'),
            const SizedBox(height: 8),
            _CodeCard(
              code: _gtmHeadSnippet,
              onCopy: () => _copy(context, _gtmHeadSnippet, 'GTM head 코드'),
            ),
            const SizedBox(height: 16),

            // GTM Body 코드
            _SectionTitle('GTM 코드 — <body> 태그 바로 다음에 삽입'),
            const SizedBox(height: 8),
            _CodeCard(
              code: _gtmBodySnippet,
              onCopy: () => _copy(context, _gtmBodySnippet, 'GTM body 코드'),
            ),
            const SizedBox(height: 20),

            // 플랫폼별 설치 위치 안내
            _SectionTitle('${setupData.platform} 설치 위치 안내'),
            const SizedBox(height: 8),
            _AppCard(
              color: const Color(0xFFF0FDF4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: kSuccess, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _installGuide[setupData.platform] ??
                          '위 GTM 코드를 <head>와 <body> 태그에 각각 삽입하세요.',
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 전화번호 클릭 dataLayer 코드
            _SectionTitle('전화번호 클릭 추적 코드 (${setupData.platform})'),
            const SizedBox(height: 8),
            _CodeCard(
              code: _dataLayerCode,
              onCopy: () => _copy(context, _dataLayerCode, '전화번호 클릭 코드'),
            ),
            const SizedBox(height: 32),

            // GTM 컨테이너 ID 표시
            Center(
              child: Text(
                'GTM 컨테이너 ID: $gtmPublicId',
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// 코드 카드
class _CodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;

  const _CodeCard({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  label: const Text('복사',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              code,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF94D2BD),
                  height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
// 공통 위젯
// ════════════════════════════════════════════

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String step;

  const _AppBar({required this.title, required this.step});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(step,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  final Widget child;
  final Color color;

  const _AppCard({required this.child, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
}

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StepHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      );
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            if (required)
              const Text(' *',
                  style: TextStyle(color: kError, fontSize: 14)),
          ],
        ),
      );
}

InputDecoration _inputDeco({required String hint, required IconData icon}) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
    );

class _PermItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;

  const _PermItem(
      {required this.icon,
      required this.color,
      required this.title,
      required this.desc});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF64748B))),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF374151)),
      );
}
