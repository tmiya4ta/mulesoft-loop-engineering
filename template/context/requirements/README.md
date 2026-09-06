# context/requirements/ — 要件の置き場所

ここに置いたものを `/mule-start` が最初に読む。形式は問わない (Markdown / PDF / スクショ / DDL / RAML)。
何を書けばよいか分からなければ `_template.md` をコピーして埋める。**全部埋まっていなくてよい。**
空欄は `/mule-start` が資料と対話で埋める。ただし **データモデル** だけは仮定で作らないので、
System 層 (DB / SaaS を包む API) では DDL かオブジェクト定義を必ず置く。

置いたら `../sources.yaml` の `requirements.paths` にパスを書く。
