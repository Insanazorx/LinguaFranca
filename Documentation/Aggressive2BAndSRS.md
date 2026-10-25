# Aggressive 2B ve kart sistemi — 24 Ekim 2026

## Uygulanan davranış

Balanced, Qwen3.5-0.8B ve mevcut bağımsız sözlük/değiştirme motoruyla devam eder. Aggressive, kullanıcının onayladığı ayrı Qwen3.5-2B Q4_K_M modelini kullanır. İki model uygulamaya paketlenir; çalışma sırasında mod değişiminde önce diğer model serbest bırakılır. Çalışan uygulama model veya sözlük indirmez.

Aggressive model İngilizce aslı ve eşleşmeleri birlikte JSON olarak üretir. Kapsam denetleyicisi İngilizce aslı ayrı tutar, seçili sınıfları çözümler, tekrarlanan ifadeleri ve UTF-16 aralıklarını eşler. Eksik/geçersiz eşleşmeler en fazla sekiz ifadeli onarım isteklerine gider. Tam İngilizce kaynak üretilmişse, eşleşme çıktısı kaynak bütçesinde kesilse bile kaynak ekranda korunur. Tamamlanmamış eşleşmeler bitmiş metin gibi gösterilmez. Remix de Aggressive model akışını kullanır.

Almanca, Rusça, Arapça, İbranice ve Süryanicenin herhangi iki veya üçlü seçimi desteklenir. Varsayılan “All selected languages” seçimi ifadeleri etkin diller arasında dağıtır. Kategoriye belirli bir dil atamak isteğe bağlıdır. Sıklık kontrolü yalnız Balanced için geçerlidir. Arapça/İbranice serbest model ifadesi kullanabilir; bağlaç/edat onarımları, bulunduğunda gerçek yerel sözlük karşılıklarıyla sınırlandırılır. Mevcut bağlam kuralları doğrulayabildikleri işlev kelimelerini ayrıca kontrol eder.

Süryanice için serbest model metni kullanılmaz. Karşılıklar yalnız ETCBC kaynaklı gerçek sözlük/korpus kayıtlarından gelir; alternatif varsa model sadece bu sabit seçeneklerden birini seçebilir. Bulunmayan karşılıklar diğer seçili dillere dağıtılır. Uygun Süryanice karşılık bulunamazsa bu dilin metinde yer almadığı açıkça bildirilir. Kaynak sözlük kimliği ve kök bağlantısı korunur. Bu davranış her sınıf/dil için eşit sözlük kapsamı veya yeni Süryanice dilbilgisi sentezi iddiası taşımaz. Önceki, tamamen Süryanice metin üreten korpus çerçeveleri korunur.

Kullanıcının son önceliği kelime anlamı ve kapsamdır; kusursuz çekim ve bütün hedef dil dilbilgisi bu aşamanın şartı değildir. Modelin bağlam seçimi insan denetimiyle sertifikalandırılmış değildir. Otomatik “complete” işareti seçili ifade kapsamını belirtir; anlamsal/dilbilgisel kusursuzluk belgesi değildir.

## Kartlar ve FSRS 6

Study içinde liste veya bütün kütüphane seçilir. Kartta hedef ifade görünür; dokununca İngilizce anlam, sözcük türü, sözlük biçimi ve varsa örnekler açılır. Sağa kaydırma Good (“biliyorum”), sola kaydırma Again (“bilmiyorum”) kaydeder. Arka yüzde More ratings üzerinden Hard/Easy de kullanılabilir. Düğmeler ve erişilebilirlik eylemleri kaydırmaya alternatif sunar.

- forgotten: son değerlendirme Again.
- studying: yeni kart veya öğrenme aşaması.
- learned: FSRS Review aşamasına geçmiş kart; daha sonra Again verilirse forgotten olur.

FSRS 6'nın 21 varsayılan ağırlığı ve resmî formülleri Swift'e taşındı. Öğrenme 1 ve 10 dakika; yeniden öğrenme 10 dakika; varsayılan hedef hatırlama %90. Rastgele interval fuzz uygulanmaz. İleri tekrar aralıkları FSRS tarafından belirlenir; “learned” kalıcı ve geri alınamaz bir etiket değildir.

v4 göçü mevcut kartları/kelimeleri/geçmişi silmeden öğrenme adımı, ilerleme durumu ve önce/sonra kart kayıtlarını ekler. Her değerlendirme kart güncellemesiyle aynı SQLite işleminde yazılır. Yinelenen/eski kart gönderimleri çift değerlendirme oluşturmaz. Ortak kelimenin farklı listelerde tek programı vardır. Liste silmek geçmişi silmez. Günlük hedef yeni/uzun süreli kart kabulünü sınırlar; süresi gelmiş öğrenme tekrarları gizlenmez. Aktif oturum kartları sabit bir kopyadan açılır; ekranın arka plandaki sayaç yenilemesi kart atlatmaz.

Üretilen okuma metinleri yine yalnız süreç belleğindedir. Kartlar, kaydedilen örnekler ve çalışma geçmişi kapanıştan sonra korunur.

## Doğrulama

- 83 Swift çekirdek + 4 model katmanı testi ve 14 Python kurulum testi geçti. `./build.sh --test --offline` son sürüm için başarılı oldu.
- FSRS 6, sabitlenmiş resmî Python uygulamasından alınan 17 referans vektörüyle karşılaştırıldı. Dört değerlendirme, kısa/uzun aralık, mezuniyet ve yeniden öğrenme kapsanır.
- Beş dilin 10 ikili + 10 üçlü kombinasyonu aynı metindeki dağıtım, gerçek Süryanice kayıtları ve Unicode aralıkları için test edildi. Bu testlerin tümü gerçek LLM dilsel kalite testi değildir.
- Gerçek Qwen3.5-2B Mac/Metal denemeleri: Almanca/Rusça birlikte; ayrıca Arapça/İbranice/Süryanice birlikte üretildi. Son Semitik deneme 121 İngilizce kelime, 25/25 seçili ifade, 13 Arapça + 11 İbranice + 1 korpus Süryanicesi eşleşmesi üretti; Mac'te 24.08 saniye. Bu iPhone süresi değildir. İlk başarısız denemeler de günlüklerde tutuldu.
- Simülatörde dokunarak çevirme, sağa/sola gerçek sürükleme, “2 reviews saved”, forgotten=1/studying=1 ve kapanıştan sonra reviews=2 korunması görüldü. Süresi gelen kısa tekrar yeniden kuyruğa girdi. Testler ayrı geliştirme kütüphanesinde yapıldı; asıl kullanıcı kelimeleri değerlendirilmedi.
- Çevrimdışı build, iki GGUF boyut/özet kontrolü, beş dilin SQLite bütünlüğü, yazı tipi ve lisans paketleme kontrolleri çalıştırıldı.
- Fiziksel iPhone 13'te bu 2B sürümünün hız/RAM/ısınma ve uçak modunda ilk açılış testi yapılmadı. Kurulu iOS 27.1, iPhone 13 simülatör tipini uyumsuz olarak reddetti; ekran testi mevcut iPhone Duo simülatöründe yapıldı.

Sonraki önerilen adım: kullanıcının gerçek okuma/kart denemesi ve fiziksel iPhone 13 üzerinde 2B bellek/hız ölçümü. Çekim incelikleri bu aşamada ek işi durdurma nedeni değildir.

## Bu aşamadaki dosyalar

Yeni: `Core/Generation/AggressiveGeneration.swift`, `Core/SRS/FSRS6.swift`, `Core/Persistence/StudyRepository.swift`, `Inference/ModeGenerationService.swift`, `Resources/Models/aggressive-model-manifest.json`, `Resources/FSRS-LICENSE.txt`, `Tools/aggressive_bootstrap.py`, `Tools/ModelSmoke/AggressiveModelChecks.swift`, `Tests/CoreTests/AggressiveModelTests.swift`, `Tests/CoreTests/SRSTests.swift`, `Tests/Fixtures/fsrs6-reference.json`, bu belge.

Güncellenen: `App/AppEnvironment.swift`, `Core/Domain/Models.swift`, `Core/Generation/TextGenerationService.swift`, `Core/Languages/LanguagePack.swift`, `Core/Persistence/DatabaseManager.swift`, `Inference/LlamaCppService.swift`, `Features/Generate/GenerateView.swift`, `Features/Study/StudyView.swift`, `Features/Settings/SettingsView.swift`, `Features/Vocabulary/VocabularyLanguageGroupView.swift`, `UIComponents/ReadingOptionsView.swift`, `Tools/build.py`, `Tools/generate_project.py`, `Tools/verify_app_bundle.py`, `Tools/ModelSmoke/main.swift`, `Tests/CoreTests/PersistenceTests.swift`, `Tests/CoreTests/SemiticTests.swift`, `Documentation/Dependencies.lock.json`, `Resources/THIRD-PARTY-NOTICES.txt`, `Documentation/SemiticRoots.md`, `README.md`.

Önceden başlamış Semitic Roots değişiklikleri de çalışma ağacında korunur. Bu aşamada commit/push yapılmadı.

## Sabitlenmiş kaynaklar

[FSRS resmî uygulaması](https://github.com/open-spaced-repetition/py-fsrs/tree/9446cb06605c597a063aeee49f7d188d42e34dc2), MIT. Test vektörleri bu sürümde fuzz kapatılarak üretildi.

[Qwen3.5-2B resmî model](https://huggingface.co/Qwen/Qwen3.5-2B), Apache-2.0. [GGUF dağıtımı](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/tree/7d26695454df6de5fbcce2e58681e62dae06ce43); Q4_K_M, 1,396,198,496 bayt, SHA-256 `57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8`.
