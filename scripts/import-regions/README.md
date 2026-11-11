# Bölge verisi içe aktarma

İl / ilçe / mahalle kaynağını (F0-8) SQL seed dosyasına çevirir. Gerçek kaynak ve lisans F0-8'de seçilir; seed M1 adım 3'te üretilir.

```sh
pnpm regions:import <girdi.csv> <çıktı.sql> [--force]
```

## CSV biçimi

- UTF-8, virgülle ayrılmış, ilk satır başlık. Her satır bir mahalle.
- Başlık tam olarak: `il_kodu,il,ilce_kodu,ilce,mahalle_kodu,mahalle`
- Kodlar pozitif tam sayı ve kendi düzeyinde benzersiz. Aynı il/ilçe kodu her satırda aynı adla geçer.
- Adlar kaynaktaki gibi kalır. Arama için `ad_normalize` alanı Türkçe kurallarla (`tr-TR`) üretilir.

Örnek: [fixtures/sample.csv](fixtures/sample.csv)

## Güvenlik

- Hata varsa çıktı yazılmaz; hatalar satır numarasıyla listelenir.
- Var olan çıktı dosyasının üzerine yalnızca `--force` ile yazılır.
