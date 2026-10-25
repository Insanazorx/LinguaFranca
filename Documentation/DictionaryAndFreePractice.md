# Serbest kart çalışması ve çevrimdışı sözlük — 24 Ekim 2026

Kart, parmak hareketinin hem yatay hem dikey bileşenini doğrudan takip eder. Hareket global koordinatlarla izlenir; kartın kendi dönüşü/sürüklenmesi tutuş noktasını kaydırmaz. Tutarken gölge ve hafif ölçek değişir. Yeterli yatay hareketle sağa bırakma Good, sola bırakma Again kaydeder. Dikey/ağırlıklı dikey veya kısa bırakma not vermeden yay animasyonuyla merkeze döner. Başarılı kayıt sonrası kart dışarı uçar. Hata durumunda aynı kart merkezde korunur. Ayrıntı kaydırması ayrı bir görünümde olduğundan kartın dikey hareketiyle yarışmaz.

Study artık tekrar tarihlerini ve günlük kabul sınırlarını kullanarak kart saklamaz. Bütün kayıtlı kelimeler, seçilen liste, tek bir kelime veya arama sonucu istenen anda çalışılabilir. Normal ekranlardaki forgotten/studying/learned rozetleri, sayaçları ve günlük/süre sınırı metinleri kaldırıldı. Bu durumlar ve FSRS 6 güncellemeleri içeride korunur. Ayrı Forgotten words listesi yalnızca son değerlendirmesi Again olan kelimeleri gösterir; kelime hatırlanınca listeden çıkar. Tarihi gelecekte olan kart tekrar açılabilir. Ortak listelerdeki kelimenin geçmişi çoğaltılmaz.

Dictionary ana sekmesi bütün paketlenmiş Almanca, Rusça, Arapça, İbranice ve Süryanice sözlükleri kullanır; üretim için etkinleştirilen dillerden ve yerine koyma motorunun güvenli aday filtrelerinden bağımsızdır. Semitic Roots & Morphology buraya taşındı ve eski kök/laboratuvar ekranları korunur. Beş ana sekme iPhone ekranında erişilebilir kalır.

Yerel arama dizininde 346.547 anlam/kelime/kök kaydı bulunur. Tüm entry satırları, Semitik lexeme/kök kayıtları ve alternatif çeviriler indekslenir. İngilizce, hedef dil, kaynakta bulunan transliterasyon ve anlam üzerinden arama yapılır. Tam yazılan çekimli biçimler Alman/Rus biçim dizini veya Semitik biçim indeksleri üzerinden sözlük maddesine bağlanır. Sonuçlar ve bütün biçim envanterleri sayfalıdır; 1,5 milyon Arapça biçim gibi büyük tablolar belleğe yüklenmez. Diakritik işaretler yalnız arama anahtarında sadeleşir; görüntülenen özgün metin korunur. FTS sorguları parametreli ve operatörleri alıntılanmış biçimde çalışır.

Maddede anlam, alternatif ifadeler, sözcük türü, mevcut etimoloji, kayıtlı biçimler, kök bağlantıları ve kaynaklar açılır. Kelime doğrudan mevcut/yeni çalışma listesine kaydedilebilir. Yerel ses varsa yalnız seçili ifade okunur. Süryanice için başka dil sesi taklit edilmez. Kart ayrıntıları da kaydedilmiş anlam kimliği/kök bağlantısıyla yerel sözlük açıklamasını okuyabilir; kullanıcı veritabanı şeması değiştirilmez. German/Russian biçim tablolarının bütün anlamlara kesin bağlanmadığı açıkça belirtilir.

## Dosyalar

Eklenen: Core/Dictionary/OfflineDictionary.swift; Core/SRS/CardDragDecision.swift; Features/Dictionary/DictionaryView.swift; Tools/prepare_dictionary_index.py; Tools/dictionary_bootstrap.py; Tests/CoreTests/DictionaryAndFreePracticeTests.swift; Tests/BuildTests/test_dictionary_index.py; bu belge.

Güncellenen: Features/Study/StudyView.swift; Core/Persistence/StudyRepository.swift; App/AppEnvironment.swift; App/LinguaFrancaApp.swift; Features/Vocabulary/VocabularyLanguageGroupView.swift; Features/Settings/SettingsView.swift; Features/SemiticRoots/SemiticRootsView.swift; UIComponents/TargetLanguagePassageView.swift; Tools/build.py; Tools/verify_app_bundle.py; .gitignore; README.md.

## Doğrulama ve sınırlar

- 88 çekirdek + 4 model katmanı Swift testi ve 16 Python hazırlama testi geçti. Çevrimdışı build ve paket bütünlüğü kontrolü başarılı oldu. Son teslim günlüğü .bootstrap/logs/dictionary-free-practice-final.log.
- Yeni testler: beş sözlüğün erişimi; farklı bank anlamları; Häuser ve işaretli İbranice çekimden arama; Süryanice; sayfalama; sorgu enjeksiyonuna karşı parametreleme; biçim sayfalama ve anlam kimliği; gelecek tarihli kartları serbest açma; unutulanlar listesinden çıkış; 505 kartlık listenin sınırlandırılmaması; çapraz/dikey/kısa sürükleme kararları.
- Simülatörde dikey-çapraz bırakmanın puan vermediği, sağa-aşağı ve sola-yukarı bırakmanın iki değerlendirmeyi kaydettiği görüldü. Hemen yeniden Practice 2 words etkin kaldı. Forgotten words yalnız Mond'u gösterdi. Garten tek başına tekrar açıldı.
- Dictionary'de bank araması farklı Arapça anlamları ayrı gösterdi. مَصْرِف kaydında anlam, etimoloji ve gerçek biçimler açıldı. Kelime ayrı test kütüphanesine kaydedilince Practice 3 words oldu.
- Ekran testi iPhone Duo/iOS 27.1 simülatöründe ve kullanıcının asıl kelimelerinden ayrı geliştirme kütüphanesinde yapıldı. Fiziksel iPhone 13 dokunma/hız/RAM testi yapılmadı.
- Arama dizini yaklaşık 224 MiB ek paket alanı kullanır; build.sh mevcut sözlüklerden üretir. Ek ağ kaynağı ve çalışma zamanı indirmesi yoktur. Önbellek parmak izi kaynak sözlük özetlerini ve üretici kodunu içerir; kurulum/bundle denetimi dizinin özetini de doğrular.
- Eski FSRS takvimi ve geçmişi silinmedi. Takvim halen hesaplanır, serbest çalışmayı engellemez. Commit/push bu aşamada yapılmadı.

Sonraki adım kullanıcının dokunma hissini ve sözlük aramalarını denemesidir.
