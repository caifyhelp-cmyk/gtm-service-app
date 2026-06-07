# GTM Service Test App — 빌드 가이드

## 1. Google Cloud Console 설정

### Firebase 프로젝트 생성
1. https://console.firebase.google.com → 프로젝트 만들기
2. Android 앱 추가: 패키지명 `com.caify.gtmservice`
3. `google-services.json` 다운로드 → `android/app/google-services.json` 으로 저장
4. (google-services-template.json 은 삭제해도 됨)

### OAuth 클라이언트 ID 설정
1. https://console.cloud.google.com → API 및 서비스 → 사용자 인증 정보
2. API 활성화:
   - Tag Manager API
   - Google Analytics Admin API
3. OAuth 동의 화면 설정 (외부 앱, 테스트 사용자에 본인 계정 추가)
4. Android OAuth 클라이언트 ID 생성:
   - 패키지명: `com.caify.gtmservice`
   - SHA-1: 아래 명령으로 확인
     ```
     cd android && ./gradlew signingReport
     ```

## 2. APK 빌드

```bash
# Flutter SDK 설치 확인
flutter --version

# 의존성 설치
flutter pub get

# APK 빌드
flutter build apk --release
```

빌드 결과: `build/app/outputs/flutter-apk/app-release.apk`

## 3. 테스트

APK를 안드로이드 기기에 설치 후:
1. Google 로그인 버튼 탭
2. GTM 접근 권한 있는 계정으로 로그인
3. GTM 계정 목록 + GA4 계정 목록 확인
4. "토큰 복사" → 복사된 액세스 토큰으로 API 직접 호출 가능
