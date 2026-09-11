%dw 2.0
output application/problem+json
// RFC 7807。global-error-handler の各 on-error-continue が vars.problemType / problemTitle / problemDetail / httpStatus を
// 立ててからこれを呼ぶ。instance は呼び出し元の flow が立てた vars.instance を優先し、無ければ
// attributes.requestPath (listener のベースパス込み) から /api を剥がす。
// **置き換えるもの 2 つ** (写経元のまま使うと RAML と食い違う。inventory3-api T-001 で実測):
//   (1) base は仮の URL。実際の問題種別の URL に置き換える。
//   (2) instance を出すなら、RAML の Problem 型にも instance: string を宣言する
//       (RFC 7807 では任意項目。RAML に無いまま出すと、応答が契約と食い違う)。
//       RAML に置かないと決めたなら、ここの instance の行を消す。
var base = "https://api.example.co.jp/problems/"
var instancePath = vars.instance default ((attributes.requestPath default "") replace /^\/api/ with "")
---
{
    "type": base ++ vars.problemType,
    "title": vars.problemTitle,
    "status": vars.httpStatus,
    "detail": vars.problemDetail,
    "instance": instancePath
}
