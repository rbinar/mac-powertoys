# PR Code Review Fixes

Bu doküman, tüm PR'lardaki Gemini Code Assist review yorumlarının durumunu takip eder.

---

## PR #1 — MacPowertoys rebrand and quick color access
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | medium | CHANGELOG.md (x7) | Changelog girişlerinden tarih/saat damgaları kaldırılmalı | ✅ Düzeltildi |
| 2 | medium | ContentView.swift | `NSApplication.terminate` yerine düzgün çıkış mekanizması | ✅ PR#4'te düzeltildi |
| 3 | medium | README.md (x5) | macOS sürüm gereksinimi, kırık gif referansı, güncel olmayan kullanım talimatları | ✅ PR#4-7'de düzeltildi |
| 4 | medium | RELEASE_NOTES.md | macOS sürüm gereksinimi | ✅ PR#4'te düzeltildi |

## PR #2 — Mouse Utilities module
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **critical** | MacPowertoys.entitlements | App Sandbox devre dışı | ✅ PR#4'te düzeltildi (sandbox etkinleştirildi) |
| 2 | medium | CrosshairsModel.swift | Magic number `0x3D` | ✅ PR#4'te düzeltildi (`rightOptionKeyCode` sabiti) |
| 3 | medium | CursorWrapModel.swift | Timer 120Hz → 60Hz | ✅ PR#4'te düzeltildi |
| 4 | medium | CursorWrapView.swift | Gereksiz Binding | ✅ PR#4'te düzeltildi (`$model.isEnabled`) |
| 5 | medium | FindMyMouseOverlayWindow.swift | Gradient renk uyumsuzluğu | ✅ PR#4'te düzeltildi (`bgColor.withAlphaComponent(0)`) |
| 6 | medium | MouseHighlighterModel.swift | Magic number `0x3A` | ✅ PR#4'te düzeltildi (`leftOptionKeyCode` sabiti) |
| 7 | medium | MouseUtilitiesModel.swift | Sınıf adı yanıltıcı | ✅ PR#4'te düzeltildi (`FindMyMouseModel` olarak yeniden adlandırıldı) |
| 8 | medium | MouseUtilitiesModel.swift | Magic numbers `0x3B`, `0x3E` | ✅ PR#4'te düzeltildi |

## PR #3 — Screen ruler fixes
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **high** | ScreenRulerModel.swift | Ekran kaydı izni mantığı hatalı | ✅ PR#4'te düzeltildi (captureScreensAsync hata yakalama) |
| 2 | medium | ScreenRulerModel.swift | `toolbarView!` force unwrap | ✅ PR#4'te düzeltildi (optional chaining) |
| 3 | medium | ScreenRulerOverlayView.swift | Kullanılmayan `shortcut` property | ✅ PR#4'te düzeltildi (kaldırıldı) |

## PR #4 — Address code review comments
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | medium | CHANGELOG.md | Sandbox changelog ifadesi | ✅ PR#7'de düzeltildi |
| 2 | medium | ScreenRulerModel.swift | İzin istemi akışı | ✅ PR#7'de düzeltildi |

## PR #5 — UI polish and global keyboard shortcuts
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **security-high** | ScreenRulerModel.swift | ESC tuşu `init()`'te global kaydediliyor | ✅ PR#7'de düzeltildi (`registerEscHotKey`/`unregisterEscHotKey` activate/deactivate'a taşındı) |
| 2 | medium | ContentView.swift | Tekrarlanan kart UI kodu | ✅ PR#7'de düzeltildi (`FeatureCardView` ve `CompactFeatureCard` oluşturuldu) |
| 3 | medium | ColorModel.swift | `deinit` temizliği eksik | ✅ PR#7'de düzeltildi (nil atamaları eklendi) |
| 4 | medium | ScreenRulerModel.swift | `GetEventParameter` OSStatus kontrol edilmiyor | ✅ PR#7'de düzeltildi (guard status == noErr) |

## PR #6 — ZoomIt module
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **critical** | ZoomItModel.swift | Race condition — async Task | ✅ PR#7'de düzeltildi (senkron switch/case pattern) |
| 2 | medium | ZoomItModel.swift | Kısayol ID'leri magic numbers | ✅ PR#7'de düzeltildi (`ZoomItHotKey` enum) |
| 3 | medium | ZoomItModel.swift | Zoom increment `0.1` magic number | ✅ PR#7'de düzeltildi (`zoomIncrement` sabiti) |
| 4 | medium | ContentView.swift | Tekrarlanan kart kodu | ✅ PR#7'de düzeltildi (`FeatureCardView`) |

## PR #7 — Fix remaining PR review comments
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | medium | CHANGELOG.md | Sistematik formatlama hatası — noktalar tarihten sonraya kaymış | ✅ Düzeltildi (tüm timestamp'lar kaldırıldı) |

## PR #8 — Webhook Notifier module
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **high** | WebhookNotifierModel.swift | Streaming data işleme güvensiz — partial mesajlar | ✅ Düzeltildi (data buffer mekanizması eklendi) |
| 2 | **security-medium** | WebhookNotifierModel.swift | Gizli `topicID` konsola loglanıyor | ✅ Düzeltildi (topicID logdan kaldırıldı) |
| 3 | medium | WebhookNotifierModel.swift | `try?` sessiz hata — saveTopics/loadTopics | ✅ Düzeltildi (`do-catch` + NSLog) |

## PR #9 — Awake and Mouse Jiggler
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | medium | AwakeView.swift | `durationPresets` dizisi | ✅ Zaten `private let` olarak tanımlanmış |

## PR #10 — README update
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | medium | README.md | Awake ve Mouse Jiggler ayrı maddeler olmalı | ✅ Zaten ayrı numaralı maddeler olarak düzenlenmiş |

## PR #11 — Clipboard Manager
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **critical** | ClipboardManagerModel.swift | `removeGlobalHotKey()` private ve hiç çağrılmıyor | ✅ Düzeltildi (`stopMonitoring()` içinden çağrılıyor, app termination'da çalışıyor) |
| 2 | **security-medium** | ClipboardManagerModel.swift | Clipboard geçmişi şifrelenmemiş UserDefaults'ta | ⚠️ Bilinen risk — Keychain migration gelecek sürümde planlanıyor |
| 3 | **security-medium** | ClipboardManagerModel.swift | `imageURL` path traversal açığı | ✅ Düzeltildi (`lastPathComponent` ile sanitize) |
| 4 | medium | ClipboardManagerModel.swift | `print()` → `OSLog`/`NSLog` | ✅ Düzeltildi (`NSLog` kullanılıyor) |
| 5 | medium | ClipboardManagerModel.swift | `try?` decode sessiz veri kaybı | ✅ Düzeltildi (`do-catch` + NSLog) |
| 6 | medium | ClipboardManagerView.swift | `DispatchQueue.main.asyncAfter` → `Task.sleep` | ✅ Düzeltildi |

## PR #12 — Markdown Preview
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **critical** | MarkdownPreviewModel.swift | `UTType(filenameExtension:)!` force unwrap | ✅ Düzeltildi (`UTType` safe init + fallback) |
| 2 | **critical** | MarkdownPreviewModel.swift | Manuel JS escape kırılgan | ✅ Düzeltildi (`JSONEncoder` ile güvenli encoding) |
| 3 | **high** | MarkdownPreviewModel.swift | `asyncAfter` ile WKWebView yükleme güvenilmez | ✅ Düzeltildi (`WKNavigationDelegate.didFinish` kullanılıyor) |
| 4 | **security-medium** | MarkdownPreviewModel.swift | XSS açığı — `marked.parse()` → `innerHTML` | ✅ Düzeltildi (DOMPurify ile sanitize) |
| 5 | medium | MarkdownPreviewModel.swift | Boş `catch` bloğu | ✅ Düzeltildi (NSLog eklendi) |
| 6 | medium | MarkdownPreviewModel.swift | `marked.js` CDN'den yükleniyor | ⚠️ Bilinen durum — bundle etme gelecek sürümde planlanıyor |
| 7 | medium | MarkdownPreviewModel.swift | Singleton delegate anti-pattern | ✅ Düzeltildi (instance-owned `ToolbarDelegate`) |

## PR #13 — Screen Annotation & Screen Ruler toolbar
| # | Seviye | Dosya | Sorun | Durum |
|---|--------|-------|-------|-------|
| 1 | **critical** | ScreenAnnotationModel.swift | `saveScreenshot()` sadece ilk ekranı yakalıyor | ✅ Düzeltildi (composite image tüm ekranlardan oluşturuluyor) |
| 2 | **high** | ScreenAnnotationModel.swift | Hem local hem global event monitor — çift çağrı | ✅ Düzeltildi (local monitor'lar kaldırıldı, sadece global) |
| 3 | **high** | ScreenAnnotationModel.swift | Local monitor cleanup kodu | ✅ Düzeltildi (local monitor referansları ve cleanup kaldırıldı) |

---

## Özet

| Durum | Sayı |
|-------|------|
| ✅ Düzeltildi | 54 |
| ⚠️ Bilinen / Gelecek sürüm | 2 |
| **Toplam** | **56** |

### Gelecek Sürüm İçin Planlanan
1. **ClipboardManager**: Clipboard geçmişini Keychain veya şifrelenmiş depolama ile saklamak
2. **MarkdownPreview**: `marked.js` kütüphanesini CDN yerine uygulama içinde bundle etmek

---
*Son güncelleme: 2026-02-27*
