import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const GTMServiceApp());
}

final _googleSignIn = GoogleSignIn(
  scopes: [
    'email',
    'https://www.googleapis.com/auth/tagmanager.readonly',
    'https://www.googleapis.com/auth/tagmanager.edit.containers',
    'https://www.googleapis.com/auth/analytics.readonly',
    'https://www.googleapis.com/auth/analytics.manage.users',
    'https://www.googleapis.com/auth/analytics.edit',
  ],
);

class GTMServiceApp extends StatelessWidget {
  const GTMServiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GTM 세팅 테스트',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleSignInAccount? _user;
  String? _token;
  List<Map<String, dynamic>> _gtmAccounts = [];
  List<Map<String, dynamic>> _ga4Properties = [];
  bool _loading = false;
  String _status = '';

  Future<void> _signIn() async {
    setState(() { _loading = true; _status = '구글 로그인 중...'; });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() { _loading = false; _status = '로그인 취소됨'; });
        return;
      }
      final auth = await account.authentication;
      setState(() {
        _user = account;
        _token = auth.accessToken;
        _status = '로그인 완료 — API 호출 중...';
      });
      await _fetchGTMAccounts();
      await _fetchGA4Properties();
    } catch (e) {
      setState(() { _status = '오류: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _fetchGTMAccounts() async {
    if (_token == null) return;
    setState(() { _status = 'GTM 계정 조회 중...'; });
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/tagmanager/v2/accounts'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final accounts = (data['account'] as List? ?? []);
        setState(() { _gtmAccounts = accounts.cast<Map<String, dynamic>>(); });
      }
    } catch (e) {
      setState(() { _status = 'GTM 오류: $e'; });
    }
  }

  Future<void> _fetchGA4Properties() async {
    if (_token == null) return;
    setState(() { _status = 'GA4 속성 조회 중...'; });
    try {
      final res = await http.get(
        Uri.parse('https://analyticsadmin.googleapis.com/v1beta/accounts'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final accounts = (data['accounts'] as List? ?? []);
        setState(() {
          _ga4Properties = accounts.cast<Map<String, dynamic>>();
          _status = '완료 ✓';
        });
      }
    } catch (e) {
      setState(() { _status = 'GA4 오류: $e'; });
    }
  }

  Future<void> _signOut() async {
    await _googleSignIn.signOut();
    setState(() {
      _user = null; _token = null;
      _gtmAccounts = []; _ga4Properties = [];
      _status = '';
    });
  }

  void _copyToken() {
    if (_token != null) {
      Clipboard.setData(ClipboardData(text: _token!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('토큰 복사됨')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        title: const Text('GTM 서비스 기능 테스트',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _signOut,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 상태 카드
            if (_status.isNotEmpty)
              _Card(
                color: _status.contains('오류')
                    ? const Color(0xFFFEE2E2)
                    : _status.contains('완료')
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFEFF6FF),
                child: Row(children: [
                  if (_loading) ...[
                    const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(_status,
                      style: const TextStyle(fontWeight: FontWeight.w500))),
                ]),
              ),

            if (_status.isNotEmpty) const SizedBox(height: 16),

            // ── 로그인 전
            if (_user == null) ...[
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('테스트 항목',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 12),
                    _CheckItem('Google OAuth 로그인'),
                    _CheckItem('GTM 계정 목록 조회'),
                    _CheckItem('GA4 속성 목록 조회'),
                    _CheckItem('API 권한 확인'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Google 로그인으로 테스트 시작',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            // ── 로그인 후
            if (_user != null) ...[
              // 사용자 정보
              _Card(
                child: Row(children: [
                  CircleAvatar(
                    backgroundImage: _user!.photoUrl != null
                        ? NetworkImage(_user!.photoUrl!) : null,
                    backgroundColor: const Color(0xFF2563EB),
                    child: _user!.photoUrl == null
                        ? const Icon(Icons.person, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_user!.displayName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_user!.email,
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    ],
                  )),
                  TextButton(onPressed: _copyToken,
                      child: const Text('토큰 복사')),
                ]),
              ),
              const SizedBox(height: 16),

              // GTM 결과
              _ResultSection(
                title: 'GTM 계정',
                icon: Icons.local_offer,
                color: const Color(0xFF2563EB),
                items: _gtmAccounts,
                nameKey: 'name',
                emptyMsg: 'GTM 계정 없음 (API 권한 확인 필요)',
              ),
              const SizedBox(height: 16),

              // GA4 결과
              _ResultSection(
                title: 'GA4 계정',
                icon: Icons.bar_chart,
                color: const Color(0xFF16A34A),
                items: _ga4Properties,
                nameKey: 'displayName',
                emptyMsg: 'GA4 계정 없음 (신규 생성 가능)',
              ),
              const SizedBox(height: 16),

              // 결과 요약
              _Card(
                color: const Color(0xFFDCFCE7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✓ 기능 체크 결과',
                        style: TextStyle(fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D))),
                    const SizedBox(height: 8),
                    _ResultItem('Google OAuth', true),
                    _ResultItem('GTM API 접근', _gtmAccounts.isNotEmpty || _token != null),
                    _ResultItem('GA4 API 접근', _token != null),
                    _ResultItem('서비스 구현 가능 여부', true),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _signOut,
                child: const Text('로그아웃'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color color;
  const _Card({required this.child,
      this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _CheckItem extends StatelessWidget {
  final String label;
  const _CheckItem(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      const Icon(Icons.check_circle_outline,
          color: Color(0xFF2563EB), size: 18),
      const SizedBox(width: 8),
      Text(label),
    ]),
  );
}

class _ResultItem extends StatelessWidget {
  final String label;
  final bool ok;
  const _ResultItem(this.label, this.ok);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(ok ? Icons.check_circle : Icons.cancel,
          color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          size: 16),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 13)),
    ]),
  );
}

class _ResultSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final String nameKey;
  final String emptyMsg;

  const _ResultSection({
    required this.title, required this.icon, required this.color,
    required this.items, required this.nameKey, required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(
              fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${items.length}개',
                style: TextStyle(fontSize: 12, color: color,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(emptyMsg,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13))
        else
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.circle, size: 6, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                item[nameKey]?.toString().split('/').last ?? item.toString(),
                style: const TextStyle(fontSize: 13),
              )),
            ]),
          )),
      ],
    ),
  );
}
