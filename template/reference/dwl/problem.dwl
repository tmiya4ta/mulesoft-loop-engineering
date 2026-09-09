%dw 2.0
output application/problem+json
// RFC 7807。global-error-handler の各 on-error-continue が vars.problemType / problemTitle / problemDetail / httpStatus を
// 立ててからこれを呼ぶ。instance は呼び出し元の flow が立てた vars.instance を優先し、無ければ
// attributes.requestPath (listener のベースパス込み) から /api を剥がす。
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
