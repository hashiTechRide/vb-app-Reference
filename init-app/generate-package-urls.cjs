/**
 * generate-package-urls.js
 * 
 * package-lock.json から全依存パッケージのダウンロードURLを抽出し、
 * package-urls.txt を生成するスクリプト。
 * 
 * 使い方:
 *   node generate-package-urls.js
 * 
 * ライブラリを追加・更新・削除した後、npm install を実行してから
 * このスクリプトを実行して package-urls.txt を再生成すること。
 */

const fs = require('fs');
const path = require('path');

const LOCKFILE_PATH = path.join(__dirname, 'package-lock.json');
const OUTPUT_PATH = path.join(__dirname, 'package-urls.txt');

// -------------------------------------------------------
// 1. package-lock.json の存在確認
// -------------------------------------------------------
if (!fs.existsSync(LOCKFILE_PATH)) {
  console.error('Error: package-lock.json が見つかりません。');
  console.error('先に npm install を実行してください。');
  process.exit(1);
}

const lockfile = JSON.parse(fs.readFileSync(LOCKFILE_PATH, 'utf-8'));
const urls = new Set();

// -------------------------------------------------------
// 2. lockfileVersion に応じてURLを抽出
// -------------------------------------------------------

// lockfileVersion 2 / 3 (npm 7+)
if (lockfile.packages) {
  for (const [pkgPath, info] of Object.entries(lockfile.packages)) {
    if (info.resolved && info.resolved.startsWith('https://')) {
      urls.add(info.resolved);
    }
  }
}

// lockfileVersion 1 (npm 6以前) — フォールバック
if (lockfile.dependencies) {
  function extractFromDeps(dependencies) {
    for (const [name, info] of Object.entries(dependencies)) {
      if (info.resolved && info.resolved.startsWith('https://')) {
        urls.add(info.resolved);
      }
      if (info.dependencies) {
        extractFromDeps(info.dependencies);
      }
    }
  }
  extractFromDeps(lockfile.dependencies);
}

// -------------------------------------------------------
// 3. ソートして出力
// -------------------------------------------------------
const sorted = [...urls].sort();

if (sorted.length === 0) {
  console.error('Warning: URLが1件も見つかりませんでした。');
  console.error('package-lock.json の内容を確認してください。');
  process.exit(1);
}

fs.writeFileSync(OUTPUT_PATH, sorted.join('\n') + '\n', 'utf-8');

console.log('========================================');
console.log('  package-urls.txt を生成しました');
console.log('========================================');
console.log('');
console.log(`  パッケージ数: ${sorted.length}`);
console.log(`  出力先:       ${OUTPUT_PATH}`);
console.log('');
console.log('次のステップ:');
console.log('  1. download-packages.ps1 を実行してパッケージをダウンロード');
console.log('  2. npm-packages/ フォルダを開発環境PCにコピー');
console.log('  3. install-offline.ps1 でオフラインインストール');
