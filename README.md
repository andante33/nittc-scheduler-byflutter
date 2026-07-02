# nittc-scheduler-byflutter

鶴岡工業高等専門学校専用時間割アプリ<br>
Android・iOS・Webに対応しています<br>
(Windows版は開発中)<br>

### 現在は、Android・iOSともにWeb版の使用をおすすめしています<br>

## 概要
既に鶴岡工業高等専門学校専用の時間割アプリは存在しているが、iOSには対応していないことから本アプリを開発した<br>

## 機能

* 時間割管理 (教科・担当教員・授業場所)
* A週・B週の自動切り替え
* 休講、補講に対応
* 時間割と紐づけた課題・予定管理
* 時間割様式の設定機能 (コマ数や授業時間等を設定できるため、高専だけでなく一般校でも使用可能です)
* 次の授業を通知
* 授業中の通知をオフにする

**注** v1.0.0ではほとんどの機能に対応していません

## 開発環境
* Flutter
* Dart
* VScode

## 導入方法

<details>
 <summary>Android版</summary>

* apkファイルをダウンロードする場合<br>

 1. Releaseをタップ
 2. 最新バージョンの.apkファイルをダウンロード
 3. ダウンロードした.apkファイルをタップしてインストール

* Webからインストールする場合
 1. [こちらをタップ](https://andante33.github.io/nittc-scheduler-byflutter)
 2. GoogleChromeで開き、右上の3つの点をタップ
 3. 「**ダウンロード**」をタップ
 4. 「**アプリをインストール**」をタップ

</details>

<details>
 <summary>iOS版</summary>

 1. [こちらをタップ](https://andante33.github.io/nittc-scheduler-byflutter)
 2. Safariを使用して開く
 3. 画面下部にある「**共有**」アイコンをタップする
 4. メニューを下にスクロールし、「**ホーム画面に追加**」をタップする
 5. 右上の「**追加**」をタップする

**注** 初期起動には少し時間がかかります

</details>

<details>
 <summary>Web版</summary>

 [こちらをタップ](https://andante33.github.io/nittc-scheduler-byflutter/)
 
</details>

## ライセンス
MIT Licenseです<br>
改変しても結構です<br>

## 動作環境済

* GooglePixel9a
* iPhone 17 Pro

**注** iPhoneでは、通知が送信されません

## 更新履歴

* **v1.0.0** (2026-06-25)<br>
  * 初版リリース
* **v1.1.0** (2026-07-01)<br>
  * Android版公開
  * Web版公開
  * iOSに対応(Web版の延長)
  * UIの改善
* **v1.1.1** (2026-07-02)<br>
  * web版の改善
    * ローディング画面の追加
    * 違う曜日に違う曜日の授業の時間割を表示させるようにした
    * フォントの改善
    * その他新規機能の追加
    * 細かなバグの改善
* **v1.1.2** (2026-07-02)<br>
  * web版の高速化
  * フォントの変更
  * 設定機能を追加
  * 細かなバグの改善
  * 細かなバグの改善
  * 新規機能を追加
