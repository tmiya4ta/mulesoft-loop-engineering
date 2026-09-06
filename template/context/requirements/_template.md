# <API 名> の要件

## 1. 目的 (1〜3 行)
<誰が、何のために、何をできるようになるか>

## 2. 利用者
- 呼ぶ側: <画面 / 他システム / 他 API>
- 想定の呼び出し頻度: <例: 1 日 1 万回、ピーク 10 req/s>

## 3. データモデル (System 層は必須。仮定で作らない)
<DB なら DDL をそのまま貼る。SaaS ならオブジェクト名と項目一覧。既存の RAML / JSON Schema があればパス>

```sql
-- 例
CREATE TABLE orders (
  id          VARCHAR(20) PRIMARY KEY,
  customer_id VARCHAR(20) NOT NULL,
  status      VARCHAR(10) NOT NULL,   -- NEW | PAID | SHIPPED | CANCELLED
  total       DECIMAL(12,2) NOT NULL,
  updated_at  TIMESTAMP NOT NULL
);
```

| 項目 | 型 | 必須 | 意味 / 制約 |
|---|---|---|---|
| id | string | ○ | 注文番号。先頭 ORD- |
| status | enum | ○ | NEW / PAID / SHIPPED / CANCELLED |

- 主キーと一意制約:
- 外部キーと参照先:
- API に出さない項目 (内部のみ):

## 4. 操作 (1 行 1 操作)
| 操作 | 入力 | 出力 | 備考 |
|---|---|---|---|
| 注文を 1 件取る | 注文番号 | 注文 | 無ければ 404 |
| 注文を検索する | 顧客番号、状態 | 注文の一覧 | ページング |
| 注文を作る | 顧客番号、明細 | 作った注文 | 採番はサーバ |

## 5. 失敗するケースと返し方
| ケース | 返すもの |
|---|---|
| 注文番号が存在しない | 404 |
| 入力の形式が違う | 400 と項目名 |
| DB に接続できない | 502 |

## 6. 入出力の例 (あれば。samples/ の元になる)
```json
// GET /orders/ORD-001 → 200
{"id":"ORD-001","customerId":"C-01","status":"PAID","total":1200.00}
```

## 7. 認証と制限
- 呼ぶ側の認証: <なし / client-id / JWT>
- レート制限: <あれば>

## 8. 接続先
- 種別: <DB (製品と版) / Salesforce / SAP / 他 API>
- 接続情報の在りか: <context/environment/ のファイル名>

## 9. 決まっていないこと
<分からないことはここに書く。/mule-start が聞くか、既定で仮定して承認時に一覧にする>
