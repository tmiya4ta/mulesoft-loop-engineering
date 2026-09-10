# プロジェクトの骨格

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- 骨格は **CLI か MCP で作る**。手書き pom はライブラリ取得で必ず落ちる (`<extensions>true</extensions>`、`mule-application` パッケージング、Exchange と MuleSoft のリポジトリ定義、`mule-artifact.json` のどれかが欠ける)。`anypoint-cli-v4 dx mule project create <name> --group-id <組織 ID> --mule-version 4.12.2`。[G]
- 生成直後の pom に **MUnit は入っていない** (CLI も Studio も同じ)。`scripts/add-munit.sh` で足す。[G]
- CLI は mule-maven-plugin を **4.7.0 で固定する**が 4.12 系とは非互換 (`NoSuchMethodError: MuleRuntimeFeature.isEnabled`)。`scripts/fix-plugin-version.sh` で 4.10.1 に上げる。[G]
- **Mule 4.9.0 は使わない** (`mule-runtime-impl-no-services-bom` が公開されておらず、`ee:transform` を 1 つ書いた時点で MUnit が `Cannot create embedded container`)。4.10.1 以降、既定は 4.12.2。[G]
- Java は **17** (4.6 以降)。Java 25 は `java.lang.Compiler` が無く動かない。`javac` と `java` が別 JDK を指す環境があるので、スクリプトから呼ぶときは `readlink -f $(command -v java)` の隣の `javac` を使う。[S][K]
- `groupId` は **Anypoint の組織 ID (UUID)**。Exchange 経由の配備 (CH2 / RTF) はこれが要件。`com.example` のままでは配備できない。[G]
- 置き場所: フローは `src/main/mule/` (1 リソース 1 ファイル + `global.xml`)、変換は `src/main/resources/dwl/`、設定は `src/main/resources/config/*.yaml`、RAML は `api/` (pom の `<resources>` に `api/` を足さないとクラスパスに乗らず `Raml not found`)。[G]
- `mule-artifact.json` は `minMuleVersion` と `requiredProduct` を持つ。`ee:` 名前空間を 1 つ使うと `requiredProduct` が `MULE_EE` になり、MUnit が EE の器を作ろうとする (4.10.1 以降なら動く)。[G]
- `-DattachMuleSources` を付けてビルドすると jar に `META-INF/mule-src/` が入り、Studio で読める。Exchange に上げるなら付ける。[S]
  **ただしプロジェクト全体をファイルシステムから丸ごと入れ、`.gitignore` は見ない。** 秘密を持つファイルはプロジェクトの外に置く。配る前に `bash scripts/jar-leak-check.sh`。[G]
- ベンダの JDBC jar は fat jar とは限らない (依存を宣言しているだけ)。Mule の外で疎通を試すときもクラスパスを推測せず `mvn -o dependency:build-classpath` に出させる。[G]
