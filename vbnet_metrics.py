#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VB.NET 2008 CE プロジェクト メトリクス解析スクリプト
====================================================
対象: Visual Studio 2008 Compact Edition (VB.NET) プロジェクト
出力: コンソール テキスト + テキストファイル (.txt)
依存: 標準ライブラリのみ（追加インストール不要）

使い方:
    python vbnet_metrics.py <プロジェクトフォルダパス>
    python vbnet_metrics.py <プロジェクトフォルダパス> > report.txt
    python vbnet_metrics.py <プロジェクトフォルダパス> -o report.txt

例:
    python vbnet_metrics.py "C:\\Projects\\PickingApp"
    python vbnet_metrics.py "C:\\Projects\\PickingApp" -o analysis.txt
"""

import os
import re
import sys
import glob
from collections import defaultdict, Counter
from dataclasses import dataclass, field
from typing import List, Dict, Set, Tuple, Optional
from datetime import datetime
from io import StringIO


# ============================================================
# データクラス
# ============================================================

@dataclass
class MethodInfo:
    name: str
    file_path: str
    class_name: str
    access_modifier: str
    return_type: str
    params: str
    start_line: int
    end_line: int
    line_count: int = 0
    branch_count: int = 0
    max_nest_depth: int = 0
    cyclomatic_complexity: int = 1
    calls_to: List[str] = field(default_factory=list)
    global_vars_read: List[str] = field(default_factory=list)
    global_vars_write: List[str] = field(default_factory=list)
    has_db_access: bool = False
    has_network_access: bool = False

@dataclass
class GlobalVarInfo:
    name: str
    var_type: str
    declared_in: str
    modifier: str
    initial_value: str = ""
    set_locations: List[str] = field(default_factory=list)
    read_locations: List[str] = field(default_factory=list)
    referencing_functions: Set[str] = field(default_factory=set)
    referencing_files: Set[str] = field(default_factory=set)

@dataclass
class FormInfo:
    name: str
    file_path: str
    controls: List[str] = field(default_factory=list)
    dynamic_controls: List[Dict] = field(default_factory=list)
    event_handlers: List[str] = field(default_factory=list)
    navigates_to: List[str] = field(default_factory=list)

@dataclass
class BranchInfo:
    file_path: str
    method_name: str
    line_number: int
    branch_type: str
    condition: str
    target: str
    nest_depth: int

@dataclass
class FileMetrics:
    file_path: str
    file_name: str
    file_type: str
    total_lines: int = 0
    code_lines: int = 0
    comment_lines: int = 0
    blank_lines: int = 0
    class_count: int = 0
    method_count: int = 0
    max_method_lines: int = 0
    avg_method_lines: float = 0.0
    branch_count: int = 0
    max_nest_depth: int = 0
    global_var_refs: int = 0


# ============================================================
# VB.NET パーサー
# ============================================================

class VBNetParser:
    RE_CLASS = re.compile(
        r'^\s*(Public|Private|Friend|Protected)?\s*(Partial\s+)?(Class|Module|Structure)\s+(\w+)',
        re.IGNORECASE)
    RE_METHOD = re.compile(
        r'^\s*(Public|Private|Protected|Friend)?\s*(Shared\s+)?(Overrides\s+)?(Sub|Function)\s+(\w+)\s*\(([^)]*)\)(?:\s+As\s+(\w+))?',
        re.IGNORECASE)
    RE_END_BLOCK = re.compile(
        r'^\s*End\s+(Sub|Function|Class|Module|Structure|Property|If|Select|While|For|Try|With|Using|SyncLock)',
        re.IGNORECASE)
    RE_GLOBAL_VAR = re.compile(
        r'^\s*(Public|Friend)\s+(Shared\s+)?(Dim\s+|Const\s+)?(\w+)\s+As\s+(\w[\w\(\)]*(?:\s*\(.*?\))?)',
        re.IGNORECASE)
    RE_IF = re.compile(r'^\s*If\s+(.+?)\s+Then\s*$', re.IGNORECASE)
    RE_ELSEIF = re.compile(r'^\s*ElseIf\s+(.+?)\s+Then', re.IGNORECASE)
    RE_SELECT = re.compile(r'^\s*Select\s+Case\s+(.+)', re.IGNORECASE)
    RE_CASE = re.compile(r'^\s*Case\s+(.+)', re.IGNORECASE)
    RE_FOR = re.compile(r'^\s*For\s+', re.IGNORECASE)
    RE_FOREACH = re.compile(r'^\s*For\s+Each\s+', re.IGNORECASE)
    RE_WHILE = re.compile(r'^\s*(?:While|Do\s+While|Do\s+Until)\s+', re.IGNORECASE)
    RE_TRY = re.compile(r'^\s*Try\s*$', re.IGNORECASE)
    RE_CATCH = re.compile(r'^\s*Catch\b', re.IGNORECASE)
    RE_SHOW_FORM = re.compile(r'(\w+)\.(Show|ShowDialog)\b', re.IGNORECASE)
    RE_CONTROL_PROP_SET = re.compile(
        r'(\w+)\.(Text|Visible|Enabled|BackColor|ForeColor|Caption|Name|DataSource|Columns)\s*=\s*(.+)',
        re.IGNORECASE)

    DB_KEYWORDS = [
        'sqlceconnection', 'sqlcecommand', 'sqlcedatareader', 'sqlcedataadapter',
        'sqlconnection', 'sqlcommand', 'sqldatareader', 'sqldataadapter',
        'executenonquery', 'executereader', 'executescalar',
        'oledbconnection', 'oledbcommand',
        'select ', 'insert ', 'update ', 'delete ', 'create table',
        '.open()', '.fill(', 'dataset', 'datatable',
    ]
    NET_KEYWORDS = [
        'httpwebrequest', 'httpwebresponse', 'webclient', 'webrequest',
        'tcpclient', 'udpclient', 'socket', 'serialport', 'system.net',
        '.getresponse(', '.downloadstring(', '.uploadstring(',
    ]

    def __init__(self, project_path: str):
        self.project_path = project_path
        self.files: List[str] = []
        self.file_metrics: List[FileMetrics] = []
        self.methods: List[MethodInfo] = []
        self.global_vars: Dict[str, GlobalVarInfo] = {}
        self.forms: Dict[str, FormInfo] = {}
        self.branches: List[BranchInfo] = []
        self.all_lines: Dict[str, List[str]] = {}

    def discover_files(self):
        for pat in ['**/*.vb', '**/*.VB']:
            for f in glob.glob(os.path.join(self.project_path, pat), recursive=True):
                n = os.path.normpath(f)
                if n not in self.files:
                    self.files.append(n)
        self.files.sort()

    def _read(self, path: str) -> List[str]:
        for enc in ['utf-8-sig', 'utf-8', 'shift_jis', 'cp932', 'euc-jp', 'latin-1']:
            try:
                with open(path, 'r', encoding=enc) as f:
                    return f.readlines()
            except (UnicodeDecodeError, UnicodeError):
                continue
        return []

    def _classify(self, path: str, content: str) -> str:
        fn = os.path.basename(path).lower()
        if fn.endswith('.designer.vb'):
            return 'Designer'
        cl = content.lower()
        if 'inherits system.windows.forms.form' in cl or 'inherits form' in cl:
            return 'Form'
        if 'inherits system.windows.forms.usercontrol' in cl or 'inherits usercontrol' in cl:
            return 'UserControl'
        if re.search(r'^\s*module\s+', content, re.IGNORECASE | re.MULTILINE):
            return 'Module'
        return 'Class'

    def _collect_global_vars(self):
        for path in self.files:
            lines = self.all_lines.get(path, [])
            fname = os.path.basename(path)
            in_class = False
            current_class = ""
            for line in lines:
                s = line.strip()
                cm = self.RE_CLASS.match(s)
                if cm:
                    in_class = True
                    current_class = cm.group(4)
                    continue
                if re.match(r'^\s*End\s+(Class|Module|Structure)', s, re.IGNORECASE):
                    in_class = False
                m = self.RE_GLOBAL_VAR.match(s)
                if m and in_class:
                    vname = m.group(4)
                    vtype = m.group(5)
                    init = ""
                    im = re.search(r'=\s*(.+)$', s)
                    if im:
                        init = im.group(1).strip()
                    key = vname.lower()
                    if key not in self.global_vars:
                        self.global_vars[key] = GlobalVarInfo(
                            name=vname, var_type=vtype,
                            declared_in=f"{fname} ({current_class})",
                            modifier=m.group(1), initial_value=init)

    def analyze(self):
        for path in self.files:
            self.all_lines[path] = self._read(path)
        self._collect_global_vars()

        for path in self.files:
            lines = self.all_lines[path]
            content = ''.join(lines)
            fname = os.path.basename(path)
            ftype = self._classify(path, content)
            fm = FileMetrics(file_path=path, file_name=fname, file_type=ftype)
            self._line_metrics(lines, fm)
            if ftype != 'Designer':
                self._parse_methods(path, lines, fm)
                self._scan_gv_refs(path, lines, fm)
                if ftype in ('Form', 'UserControl'):
                    self._parse_form(path, lines, content)
            self.file_metrics.append(fm)

    def _line_metrics(self, lines, fm):
        fm.total_lines = len(lines)
        for line in lines:
            s = line.strip()
            if not s:
                fm.blank_lines += 1
            elif s.startswith("'") or s.upper().startswith("REM "):
                fm.comment_lines += 1
            else:
                fm.code_lines += 1

    def _parse_methods(self, path, lines, fm):
        fname = os.path.basename(path)
        current_class = ""
        method_stack = []
        nest = 0

        for i, line in enumerate(lines):
            code = re.sub(r"'.*$", '', line.strip()).strip()
            if not code:
                continue
            ln = i + 1

            cm = self.RE_CLASS.match(code)
            if cm:
                current_class = cm.group(4)
                fm.class_count += 1
                continue

            mm = self.RE_METHOD.match(code)
            if mm:
                mi = MethodInfo(
                    name=mm.group(5), file_path=fname, class_name=current_class,
                    access_modifier=mm.group(1) or "Private",
                    return_type=mm.group(7) or ("Void" if mm.group(4).lower() == 'sub' else "?"),
                    params=(mm.group(6) or "").strip(),
                    start_line=ln, end_line=ln)
                method_stack.append((mi, nest))
                nest += 1
                fm.method_count += 1
                continue

            # --- branching ---
            def _add_branch(btype, cond):
                if method_stack:
                    mi = method_stack[-1][0]
                    mi.branch_count += 1
                    mi.cyclomatic_complexity += 1
                    fm.branch_count += 1
                    self.branches.append(BranchInfo(
                        file_path=fname, method_name=mi.name,
                        line_number=ln, branch_type=btype,
                        condition=cond.strip()[:120], target="", nest_depth=nest))

            m_if = self.RE_IF.match(code)
            if m_if:
                nest += 1
                cond = m_if.group(1)
                _add_branch("If", cond)
                if method_stack:
                    method_stack[-1][0].cyclomatic_complexity += len(
                        re.findall(r'\b(And|Or|AndAlso|OrElse)\b', cond, re.IGNORECASE))
            elif self.RE_ELSEIF.match(code):
                _add_branch("ElseIf", self.RE_ELSEIF.match(code).group(1))
            elif self.RE_SELECT.match(code):
                nest += 1
                _add_branch("Select Case", self.RE_SELECT.match(code).group(1))
            elif self.RE_CASE.match(code) and not code.lower().startswith('select'):
                if method_stack and not code.strip().lower().startswith('case else'):
                    method_stack[-1][0].cyclomatic_complexity += 1
            elif self.RE_FOR.match(code) or self.RE_FOREACH.match(code):
                nest += 1
                if method_stack:
                    method_stack[-1][0].cyclomatic_complexity += 1
            elif self.RE_WHILE.match(code):
                nest += 1
                if method_stack:
                    method_stack[-1][0].cyclomatic_complexity += 1
            elif self.RE_TRY.match(code):
                nest += 1
            elif self.RE_CATCH.match(code):
                if method_stack:
                    method_stack[-1][0].cyclomatic_complexity += 1

            if method_stack:
                rel = nest - method_stack[-1][1] - 1
                if rel > method_stack[-1][0].max_nest_depth:
                    method_stack[-1][0].max_nest_depth = rel

            # Control property set → annotate branch target
            if method_stack:
                cp = self.RE_CONTROL_PROP_SET.match(code)
                if cp:
                    for bi in reversed(self.branches):
                        if bi.file_path == fname and bi.method_name == method_stack[-1][0].name and not bi.target:
                            bi.target = f"{cp.group(1)}.{cp.group(2)}"
                            break

            # DB / network
            if method_stack:
                cl = code.lower()
                for kw in self.DB_KEYWORDS:
                    if kw in cl:
                        method_stack[-1][0].has_db_access = True
                        break
                for kw in self.NET_KEYWORDS:
                    if kw in cl:
                        method_stack[-1][0].has_network_access = True
                        break

            # End block
            em = self.RE_END_BLOCK.match(code)
            if em:
                bt = em.group(1).lower()
                if bt in ('sub', 'function') and method_stack:
                    mi, _ = method_stack.pop()
                    mi.end_line = ln
                    mi.line_count = mi.end_line - mi.start_line + 1
                    self._scan_method_body(path, lines, mi)
                    self.methods.append(mi)
                nest = max(0, nest - 1)

        mlens = [m.line_count for m in self.methods if m.file_path == os.path.basename(path)]
        if mlens:
            fm.max_method_lines = max(mlens)
            fm.avg_method_lines = sum(mlens) / len(mlens)
        fm.max_nest_depth = max((m.max_nest_depth for m in self.methods if m.file_path == os.path.basename(path)), default=0)

    def _scan_method_body(self, path, lines, mi):
        for li in range(mi.start_line - 1, min(mi.end_line, len(lines))):
            code = re.sub(r"'.*$", '', lines[li]).strip()
            for key, gv in self.global_vars.items():
                pat = r'\b' + re.escape(gv.name) + r'\b'
                if re.search(pat, code, re.IGNORECASE):
                    loc = f"{mi.file_path}:{li+1}"
                    if re.search(r'\b' + re.escape(gv.name) + r'\s*=', code, re.IGNORECASE):
                        if gv.name not in mi.global_vars_write:
                            mi.global_vars_write.append(gv.name)
                        if loc not in gv.set_locations:
                            gv.set_locations.append(loc)
                    else:
                        if gv.name not in mi.global_vars_read:
                            mi.global_vars_read.append(gv.name)
                        if loc not in gv.read_locations:
                            gv.read_locations.append(loc)
                    gv.referencing_functions.add(f"{mi.class_name}.{mi.name}")
                    gv.referencing_files.add(mi.file_path)
            calls = re.findall(r'(\w+\.\w+|\w+)\s*\(', code)
            skip = {'if','while','for','select','case','catch','ctype','cstr','cint','cdbl',
                     'cbool','directcast','trycast','typeof','gettype','nothing','not','and','or'}
            for c in calls:
                if c.lower() not in skip and c not in mi.calls_to:
                    mi.calls_to.append(c)

    def _scan_gv_refs(self, path, lines, fm):
        count = 0
        for line in lines:
            code = re.sub(r"'.*$", '', line).strip()
            for gv in self.global_vars.values():
                if re.search(r'\b' + re.escape(gv.name) + r'\b', code, re.IGNORECASE):
                    count += 1
        fm.global_var_refs = count

    def _parse_form(self, path, lines, content):
        fname = os.path.basename(path)
        form_name = os.path.splitext(fname)[0]
        fi = FormInfo(name=form_name, file_path=fname)

        ctrl_pats = [
            re.compile(r'(?:Me\.)?(\w+)\s*=\s*New\s+System\.Windows\.Forms\.(\w+)', re.IGNORECASE),
            re.compile(r'Friend\s+WithEvents\s+(\w+)\s+As\s+(?:System\.Windows\.Forms\.)?(\w+)', re.IGNORECASE),
        ]
        ctrls = set()
        all_lines = lines[:]
        designer = path.replace('.vb', '.Designer.vb')
        if os.path.exists(designer):
            all_lines += self._read(designer)
        for line in all_lines:
            for p in ctrl_pats:
                m = p.search(line)
                if m:
                    ctrls.add(f"{m.group(1)} ({m.group(2)})")
        fi.controls = sorted(ctrls)

        hp = re.compile(r'(?:Private|Public|Protected)\s+Sub\s+(\w+_\w+)\s*\(', re.IGNORECASE)
        for line in lines:
            m = hp.match(line.strip())
            if m:
                fi.event_handlers.append(m.group(1))

        for line in lines:
            m = self.RE_SHOW_FORM.search(line)
            if m and m.group(1) not in fi.navigates_to:
                fi.navigates_to.append(m.group(1))

        for li, line in enumerate(lines):
            code = re.sub(r"'.*$", '', line).strip()
            m = self.RE_CONTROL_PROP_SET.match(code)
            if m:
                fi.dynamic_controls.append({
                    'control': m.group(1), 'property': m.group(2),
                    'value': m.group(3).strip()[:60], 'line': li + 1})

        self.forms[form_name] = fi


# ============================================================
# テキストレポート生成
# ============================================================

class TextReport:
    def __init__(self, parser: VBNetParser):
        self.p = parser
        self.buf = StringIO()
        self.sep_thick = "=" * 90
        self.sep_thin = "-" * 90
        self.sep_dot = "." * 90

    def w(self, text=""):
        self.buf.write(text + "\n")

    def header(self, title, level=1):
        self.w()
        if level == 1:
            self.w(self.sep_thick)
            self.w(f"  {title}")
            self.w(self.sep_thick)
        elif level == 2:
            self.w(self.sep_thin)
            self.w(f"  {title}")
            self.w(self.sep_thin)
        else:
            self.w(f"  --- {title} ---")

    def table(self, headers, rows, widths=None):
        """固定幅テーブルを出力"""
        if not widths:
            widths = []
            for ci, h in enumerate(headers):
                col_vals = [str(r[ci]) if ci < len(r) else "" for r in rows]
                w = max(len(h), max((len(v) for v in col_vals), default=0))
                widths.append(min(w + 2, 40))

        def fmt_row(vals):
            parts = []
            for i, v in enumerate(vals):
                w = widths[i] if i < len(widths) else 20
                s = str(v)
                # 日本語の幅を考慮した簡易パディング
                disp_len = 0
                for ch in s:
                    disp_len += 2 if ord(ch) > 0x7F else 1
                pad = max(0, w - disp_len)
                parts.append(s + " " * pad)
            return "  " + " | ".join(parts)

        self.w(fmt_row(headers))
        self.w("  " + "+".join("-" * w for w in widths))
        for row in rows:
            self.w(fmt_row(row))

    def generate(self) -> str:
        self._title()
        self._summary()
        self._file_metrics()
        self._complexity_ranking()
        self._global_vars()
        self._branch_map()
        self._form_map()
        self._method_detail()
        self._dependency_matrix()
        return self.buf.getvalue()

    # ---- Title ----
    def _title(self):
        self.w(self.sep_thick)
        self.w("  VB.NET 2008 CE プロジェクト メトリクス解析レポート")
        self.w(self.sep_thick)
        self.w(f"  解析日時 : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.w(f"  対象     : {self.p.project_path}")
        self.w(f"  ファイル数: {len(self.p.files)}")

    # ---- 1. Summary ----
    def _summary(self):
        self.header("1. サマリー")
        p = self.p
        nd = [f for f in p.file_metrics if f.file_type != 'Designer']
        total = sum(f.total_lines for f in nd)
        code = sum(f.code_lines for f in nd)
        comment = sum(f.comment_lines for f in nd)
        blank = sum(f.blank_lines for f in nd)
        nm = len(p.methods)
        avg_cc = sum(m.cyclomatic_complexity for m in p.methods) / max(1, nm)
        max_cc = max((m.cyclomatic_complexity for m in p.methods), default=0)
        max_nest = max((m.max_nest_depth for m in p.methods), default=0)
        hi_risk_m = len([m for m in p.methods if m.cyclomatic_complexity > 10])
        big_m = len([m for m in p.methods if m.line_count > 100])
        gv_count = len(p.global_vars)
        hi_risk_gv = len([g for g in p.global_vars.values() if len(g.referencing_files) >= 3])

        self.w()
        self.w("  [コード量]")
        data = [
            ("ファイル数 (Designer除く)", len(nd)),
            ("総行数", total), ("コード行", code),
            ("コメント行", comment), ("空白行", blank),
            ("コメント率", f"{comment / max(1,code) * 100:.1f}%"),
            ("フォーム数", len([f for f in nd if f.file_type == 'Form'])),
            ("モジュール数", len([f for f in nd if f.file_type == 'Module'])),
            ("クラス数", sum(f.class_count for f in nd)),
            ("メソッド数", nm),
        ]
        for label, val in data:
            self.w(f"    {label:30s} : {val}")

        self.w()
        self.w("  [複雑度]")
        for label, val in [
            ("平均循環的複雑度", f"{avg_cc:.1f}"),
            ("最大循環的複雑度", max_cc),
            ("最大ネスト深度", max_nest),
            ("高リスクメソッド (CC>10)", hi_risk_m),
            ("巨大メソッド (100行超)", big_m),
            ("総分岐数", sum(f.branch_count for f in nd)),
        ]:
            self.w(f"    {label:30s} : {val}")

        self.w()
        self.w("  [グローバル変数]")
        for label, val in [
            ("グローバル変数数", gv_count),
            ("高リスク (3ファイル以上参照)", hi_risk_gv),
            ("参照箇所 総数", sum(len(g.read_locations)+len(g.set_locations) for g in p.global_vars.values())),
        ]:
            self.w(f"    {label:30s} : {val}")

        self.w()
        self.w("  [フォーム共通化]")
        for label, val in [
            ("フォーム数", len(p.forms)),
            ("動的コントロール変更 総数", sum(len(f.dynamic_controls) for f in p.forms.values())),
            ("切替有りフォーム数", len([f for f in p.forms.values() if f.dynamic_controls])),
        ]:
            self.w(f"    {label:30s} : {val}")

        # Risk warnings
        self.w()
        self.w("  [リスク警告]")
        warnings = []
        if hi_risk_m > 0:
            warnings.append(f"!! 循環的複雑度 > 10 のメソッドが {hi_risk_m} 件。分割を検討。")
        if hi_risk_gv > 0:
            warnings.append(f"!! 3ファイル以上参照のグローバル変数が {hi_risk_gv} 件。引数化・クラス化を推奨。")
        if big_m > 0:
            warnings.append(f"!! 100行超のメソッドが {big_m} 件。")
        dyn_forms = [f for f in p.forms.values() if len(f.dynamic_controls) > 5]
        if dyn_forms:
            warnings.append(f"!! 動的変更 > 5 のフォームが {len(dyn_forms)} 件。フォーム分離を検討。")
        if not warnings:
            warnings.append("重大なリスクは検出されませんでした。")
        for w in warnings:
            self.w(f"    {w}")

    # ---- 2. File Metrics ----
    def _file_metrics(self):
        self.header("2. ファイル別メトリクス")
        nd = sorted([f for f in self.p.file_metrics if f.file_type != 'Designer'],
                     key=lambda x: x.code_lines, reverse=True)
        headers = ["ファイル名", "種別", "コード行", "コメント行", "メソッド数",
                   "最大メソッド行", "分岐数", "最大ネスト", "GV参照"]
        rows = []
        for f in nd:
            rows.append([f.file_name, f.file_type, f.code_lines, f.comment_lines,
                         f.method_count, f.max_method_lines, f.branch_count,
                         f.max_nest_depth, f.global_var_refs])
        self.table(headers, rows, [24, 12, 8, 8, 8, 10, 8, 8, 8])

    # ---- 3. Complexity Ranking ----
    def _complexity_ranking(self):
        self.header("3. 複雑度ランキング（リファクタリング優先度 Top30）")

        def score(m):
            return (m.cyclomatic_complexity * 3
                    + m.line_count * 0.1
                    + m.max_nest_depth * 5
                    + len(m.global_vars_read + m.global_vars_write) * 4)

        ranked = sorted(self.p.methods, key=score, reverse=True)[:30]
        headers = ["#", "ファイル", "クラス", "メソッド", "行数", "CC", "ネスト", "GV数", "スコア", "推奨"]
        rows = []
        for i, m in enumerate(ranked):
            s = score(m)
            gv = len(m.global_vars_read) + len(m.global_vars_write)
            if s > 50:
                act = "要分割+GV除去"
            elif s > 30:
                act = "分割推奨"
            elif s > 15:
                act = "リファクタ検討"
            else:
                act = "許容範囲"
            rows.append([i+1, m.file_path, m.class_name, m.name,
                         m.line_count, m.cyclomatic_complexity,
                         m.max_nest_depth, gv, f"{s:.0f}", act])
        self.table(headers, rows, [3, 18, 14, 22, 5, 4, 5, 4, 6, 16])

    # ---- 4. Global Variables ★ ----
    def _global_vars(self):
        self.header("4. グローバル変数 影響範囲 ★")
        if not self.p.global_vars:
            self.w("  グローバル変数は検出されませんでした。")
            return

        sorted_gv = sorted(self.p.global_vars.values(),
                           key=lambda g: len(g.referencing_files), reverse=True)

        for gv in sorted_gv:
            fc = len(gv.referencing_files)
            risk = "高" if fc >= 4 else ("中" if fc >= 2 else "低")
            marker = " ★★★" if risk == "高" else (" ★★" if risk == "中" else "")

            self.w()
            self.w(f"  [{gv.name}]{marker}  リスク: {risk}")
            self.w(f"    型          : {gv.var_type}")
            self.w(f"    宣言場所    : {gv.declared_in}")
            self.w(f"    修飾子      : {gv.modifier}")
            self.w(f"    初期値      : {gv.initial_value or '(なし)'}")
            self.w(f"    参照ファイル数: {fc}")
            self.w(f"    セット箇所数 : {len(gv.set_locations)}")
            self.w(f"    参照箇所数  : {len(gv.read_locations)}")

            if gv.set_locations:
                self.w(f"    セット箇所  :")
                for loc in gv.set_locations[:15]:
                    self.w(f"      - {loc}")
            if gv.read_locations:
                self.w(f"    参照箇所    :")
                for loc in gv.read_locations[:15]:
                    self.w(f"      - {loc}")
            if gv.referencing_functions:
                self.w(f"    参照関数    :")
                for fn in sorted(gv.referencing_functions)[:15]:
                    self.w(f"      - {fn}")

        # Summary table
        self.w()
        self.header("グローバル変数 リスク集計", 3)
        risk_counts = Counter(
            "高" if len(g.referencing_files) >= 4 else ("中" if len(g.referencing_files) >= 2 else "低")
            for g in self.p.global_vars.values())
        for level in ["高", "中", "低"]:
            self.w(f"    {level}: {risk_counts.get(level, 0)} 件")

    # ---- 5. Branch Map ----
    def _branch_map(self):
        self.header("5. 条件分岐マップ")
        if not self.p.branches:
            self.w("  分岐は検出されませんでした。")
            return

        # Group by file then method
        by_file = defaultdict(list)
        for b in self.p.branches:
            by_file[b.file_path].append(b)

        for fname, branches in sorted(by_file.items()):
            self.header(f"[{fname}]", 3)
            headers = ["行", "種別", "メソッド", "条件", "対象ctrl", "ネスト"]
            rows = []
            for b in sorted(branches, key=lambda x: x.line_number):
                target = b.target if b.target else "-"
                cond = b.condition[:50]
                rows.append([b.line_number, b.branch_type, b.method_name, cond, target, b.nest_depth])
            self.table(headers, rows, [5, 12, 22, 50, 18, 6])

        # Control switch summary
        ctrl_branches = [b for b in self.p.branches if b.target]
        if ctrl_branches:
            self.w()
            self.header("コントロール動的切替の分岐（注目）", 3)
            headers = ["ファイル", "メソッド", "行", "条件", "対象"]
            rows = [[b.file_path, b.method_name, b.line_number,
                      b.condition[:40], b.target] for b in ctrl_branches]
            self.table(headers, rows, [18, 22, 5, 40, 20])

    # ---- 6. Form Map ----
    def _form_map(self):
        self.header("6. フォーム共通化・動的コントロールマップ")
        if not self.p.forms:
            self.w("  フォームは検出されませんでした。")
            return

        for fi in sorted(self.p.forms.values(), key=lambda f: len(f.dynamic_controls), reverse=True):
            dyn = len(fi.dynamic_controls)
            marker = " ★★ フォーム分離候補" if dyn > 5 else (" ★ 要確認" if dyn > 0 else "")
            self.w()
            self.w(f"  [{fi.name}]{marker}")
            self.w(f"    コントロール数     : {len(fi.controls)}")
            self.w(f"    イベントハンドラ数 : {len(fi.event_handlers)}")
            self.w(f"    動的コントロール変更: {dyn}")
            self.w(f"    遷移先             : {', '.join(fi.navigates_to) or '-'}")

            if fi.dynamic_controls:
                self.w(f"    動的変更詳細:")
                for d in fi.dynamic_controls[:20]:
                    self.w(f"      L{d['line']:>4d}  {d['control']}.{d['property']} = {d['value']}")

            if fi.controls:
                self.w(f"    コントロール一覧:")
                for ctrl in fi.controls[:20]:
                    self.w(f"      - {ctrl}")

    # ---- 7. Method Detail ----
    def _method_detail(self):
        self.header("7. メソッド詳細一覧")
        headers = ["ファイル", "クラス", "メソッド", "修飾子", "行数", "CC", "ネスト",
                   "GV(R)", "GV(W)", "DB", "通信"]
        rows = []
        for m in sorted(self.p.methods, key=lambda x: (x.file_path, x.start_line)):
            gvr = ",".join(m.global_vars_read) if m.global_vars_read else "-"
            gvw = ",".join(m.global_vars_write) if m.global_vars_write else "-"
            rows.append([m.file_path, m.class_name, m.name, m.access_modifier,
                         m.line_count, m.cyclomatic_complexity, m.max_nest_depth,
                         gvr[:25], gvw[:25],
                         "Y" if m.has_db_access else "-",
                         "Y" if m.has_network_access else "-"])
        self.table(headers, rows, [18, 14, 22, 8, 5, 4, 5, 25, 25, 3, 3])

    # ---- 8. Dependency Matrix ----
    def _dependency_matrix(self):
        self.header("8. ファイル間依存関係マトリクス")
        self.w("  行 = 呼出元, 列 = 呼出先. 数値 = メソッド呼出回数.")
        self.w()

        files = sorted(set(m.file_path for m in self.p.methods))
        if not files:
            self.w("  データなし")
            return

        idx = {f: i for i, f in enumerate(files)}
        n = len(files)
        mat = [[0]*n for _ in range(n)]
        c2f = {}
        for m in self.p.methods:
            c2f[m.class_name.lower()] = m.file_path
        for m in self.p.methods:
            si = idx.get(m.file_path)
            if si is None:
                continue
            for call in m.calls_to:
                parts = call.split('.')
                tc = parts[0].lower() if len(parts) > 1 else m.class_name.lower()
                tf = c2f.get(tc, m.file_path)
                di = idx.get(tf)
                if di is not None:
                    mat[si][di] += 1

        # Short names for display
        short = [f.replace('.vb', '')[:12] for f in files]
        cw = max(len(s) for s in short) + 1
        cw = max(cw, 5)

        # Header row
        hdr = " " * (cw + 2) + "".join(s.rjust(cw) for s in short)
        self.w(f"  {hdr}")
        self.w(f"  {'-' * len(hdr)}")

        for i, fname in enumerate(short):
            row_str = fname.ljust(cw) + " |"
            for j in range(n):
                v = mat[i][j]
                row_str += (str(v) if v > 0 else ".").rjust(cw)
            self.w(f"  {row_str}")

        # Cross-file dependencies summary
        self.w()
        self.header("ファイル間依存 サマリー（自ファイル除く）", 3)
        deps = []
        for i in range(n):
            for j in range(n):
                if i != j and mat[i][j] > 0:
                    deps.append((files[i], files[j], mat[i][j]))
        deps.sort(key=lambda x: x[2], reverse=True)
        if deps:
            headers = ["呼出元", "呼出先", "回数"]
            rows = [[d[0], d[1], d[2]] for d in deps[:20]]
            self.table(headers, rows, [22, 22, 6])
        else:
            self.w("  ファイル間の依存はありません。")


# ============================================================
# メイン
# ============================================================

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print("=" * 60)
        print("VB.NET 2008 CE メトリクス解析スクリプト")
        print("=" * 60)
        print()
        print("使い方:")
        bn = os.path.basename(__file__)
        print(f"  python {bn} <プロジェクトフォルダ>")
        print(f"  python {bn} <プロジェクトフォルダ> > report.txt")
        print(f"  python {bn} <プロジェクトフォルダ> -o report.txt")
        print()
        print("依存ライブラリ: なし（標準ライブラリのみ）")
        sys.exit(0)

    project_path = os.path.abspath(sys.argv[1])
    if not os.path.isdir(project_path):
        print(f"エラー: ディレクトリが見つかりません: {project_path}", file=sys.stderr)
        sys.exit(1)

    output_file = None
    if '-o' in sys.argv:
        oi = sys.argv.index('-o')
        if oi + 1 < len(sys.argv):
            output_file = sys.argv[oi + 1]

    # Parse
    print("解析中...", file=sys.stderr)
    parser = VBNetParser(project_path)
    parser.discover_files()
    if not parser.files:
        print("エラー: .vb ファイルが見つかりませんでした。", file=sys.stderr)
        sys.exit(1)
    print(f"  ファイル数: {len(parser.files)}", file=sys.stderr)
    parser.analyze()
    print(f"  メソッド数: {len(parser.methods)}", file=sys.stderr)
    print(f"  グローバル変数数: {len(parser.global_vars)}", file=sys.stderr)
    print(f"  フォーム数: {len(parser.forms)}", file=sys.stderr)
    print(f"  分岐数: {len(parser.branches)}", file=sys.stderr)

    # Report
    report = TextReport(parser)
    text = report.generate()

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f"レポート出力: {os.path.abspath(output_file)}", file=sys.stderr)
    else:
        print(text)

    print("完了", file=sys.stderr)


if __name__ == '__main__':
    main()
