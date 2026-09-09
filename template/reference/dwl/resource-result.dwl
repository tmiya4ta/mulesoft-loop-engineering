%dw 2.0
output application/json
// 読み戻した 1 行 (配列) を RAML の ProfileResult に変換する。0 件は flow 側で raise-error 済みなので payload[0] は必ずある。
// 時刻はアプリで作らず DB の値をそのまま使う。TIMESTAMP 列は既に String。
var row = payload[0]
---
{
    customerId: row.CUSTOMER_ID,
    field1: row.FIELD1,
    updatedAt: row.UPDATED_AT as String
}
