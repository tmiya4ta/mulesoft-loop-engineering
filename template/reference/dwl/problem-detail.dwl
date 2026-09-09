%dw 2.0
output application/java
// APIKIT:BAD_REQUEST の error.description は "/<項目名> string [値] does not match pattern ..." で始まり、
// 複数項目なら改行で連結される。先頭の項目名だけを取り出して config/messages.yaml (起動時に読込済み) を p() で引く。
// 406 / 415 はこの形にならないので既定文にフォールバックする。
var description = (error.description default '') as String
var fieldMatches = description scan /^\/(\w+)/
var fieldName = if (isEmpty(fieldMatches)) '' else fieldMatches[0][1]
---
if (isEmpty(fieldName))
    '入力が正しくありません'
else
    (p('messages.' ++ fieldName) default '入力が正しくありません')
