# 設定とプロパティ

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- `<configuration-properties file="config/x.yaml"/>` は複数置ける。**YAML の値はすべて文字列**になる (数値が要る batch の `blockSize` などは YAML でクォートしない)。[S][K]
- `<global-property name="mule.env" value="local"/>` を **`configuration-properties` より前**に置いて既定値を作る。`${mule.env:local}` のような既定値付き参照は RTF で解決に失敗することがある。[S]
- ローカル実行 (`mvn test`) で `${x.y}` を上書きできるのは **システムプロパティ `-Dx.y=...` だけ**。OS の環境変数は `x.y` でも `X_Y` でも読まれない。CH2 / RTF では Runtime Manager の Properties が効く。[K]
- 秘密は `secure::` プロパティか配備時の secureProperty。pom / YAML / 会話に書かない。[S]
- `p('a.b.c')` で YAML のネストしたキーを動的に引ける。エラーハンドラの中で `readUrl` を使うと、その失敗が「エラーハンドラの中の 2 つ目のエラー」になって problem+json を名乗る壊れた応答を返すので、文言表は `configuration-properties` で起動時に読む。[G]
- Config 名は global と参照側で完全一致させる (`config-ref="process-api-config"`)。違うと起動時ではなく実行時に落ちる。[S]
