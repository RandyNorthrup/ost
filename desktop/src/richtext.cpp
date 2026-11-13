// The compose box's rich text, as Teams' formatting bar edits it: formats
// applied to the QTextDocument behind a QML TextEdit (cxx-qt has no
// bindings for QTextCursor), and the document written out as the small,
// clean HTML OST turns into Teams' message HTML (src/api/messages.rs).
//
// The helper item (RichText, src/rich_text.rs) sits inside the TextEdit;
// every call finds the document through its parent.
#include <QtCore/QUuid>
#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtCore/QSet>
#include <QtGui/QColor>
#include <QtGui/QSyntaxHighlighter>
#include <QtGui/QTextBlock>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtGui/QTextDocumentFragment>
#include <QtGui/QTextFrame>
#include <QtGui/QTextList>
#include <QtGui/QTextTable>
#include <QtGui/QGuiApplication>
#include <QtGui/QScreen>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickTextDocument>

#include <cstdlib>
#include <cstring>

namespace {

// Our own marks on formats (not written by Qt's HTML export).
enum : int {
    InlineCode = QTextFormat::UserProperty + 1, // char: inline code
    RuleBlock = QTextFormat::UserProperty + 5,  // block: a horizontal rule
    QuoteBlock = QTextFormat::UserProperty + 6, // block: in a quote
    CodeBlockP = QTextFormat::UserProperty + 7, // block: a code block line
    BlockLang = QTextFormat::UserProperty + 8,  // block: its code language
    HeadingWeight = QTextFormat::UserProperty + 9, // char: a heading's weight
    CodeAuto = QTextFormat::UserProperty + 10,  // block: its language auto-detected
};

// Quotes and code blocks are marked paragraphs (QQuickTextEdit can't take
// frames added while it shows the document); QML draws Teams' quote box and
// code card behind each run. Their margins make room inside the box.
void normalize(QTextDocument *doc)
{
    QTextCursor c(doc);
    for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
        const QTextBlockFormat f = b.blockFormat();
        const bool q = f.boolProperty(QuoteBlock), code = f.boolProperty(CodeBlockP);
        const QTextBlockFormat pf = b.previous().isValid() ? b.previous().blockFormat() : QTextBlockFormat();
        const QTextBlockFormat nf = b.next().isValid() ? b.next().blockFormat() : QTextBlockFormat();
        const bool first = (q && !pf.boolProperty(QuoteBlock)) || (code && !pf.boolProperty(CodeBlockP));
        const bool last = (q && !nf.boolProperty(QuoteBlock)) || (code && !nf.boolProperty(CodeBlockP));
        QTextBlockFormat want = f;
        // Quote: 7 out, 7/15 in, a hairline; code: a 32 px header, 8/12 in
        // and a 42 px gutter for line numbers.
        want.setLeftMargin(q ? 16 : code ? 54 : 0);
        want.setRightMargin(q || code ? 16 : 0);
        want.setTopMargin(first ? (q ? 14 : 32 + 8 + 4) : 0);
        want.setBottomMargin(last ? (q ? 14 : 8 + 4) : 0);
        if (code)
            want.setLineHeight(24, QTextBlockFormat::FixedHeight);
        else if (f.lineHeightType() == QTextBlockFormat::FixedHeight && f.lineHeight() == 24)
            want.setLineHeight(100, QTextBlockFormat::ProportionalHeight);
        if (want != f) {
            c.setPosition(b.position());
            c.setBlockFormat(want);
        }
        // Code is Cascadia Mono 14, whatever was pasted or typed into it.
        if (code && b.length() > 1) {
            QTextCursor all(b);
            all.movePosition(QTextCursor::EndOfBlock, QTextCursor::KeepAnchor);
            QTextCharFormat mono;
            mono.setFontFamilies({QStringLiteral("Cascadia Mono")});
            mono.setProperty(QTextFormat::FontPixelSize, 14);
            bool needed = false;
            for (auto it = b.begin(); !it.atEnd(); ++it)
                if (it.fragment().charFormat().fontFamilies().toStringList() != QStringList{QStringLiteral("Cascadia Mono")})
                    needed = true;
            if (needed)
                all.mergeCharFormat(mono);
        }
    }
}

const char *Mono = "Cascadia Mono";

// Teams' compose colours code blocks with highlight.js, folded into five
// classes (measured on winpc 2026-11-10, CKEditor's code block): strings
// and numbers #237B4B; keywords, types, meta and tag names #4F52B2;
// functions being defined, class names, built-ins and attributes #C4314B;
// comments #707070; the rest #242424. (Dark colours: Fluent's dark
// foregrounds for the same roles; not measured.)
struct CodeLang {
    QSet<QString> keywords;  // hljs keyword, type, meta, name
    QSet<QString> builtins;  // hljs built_in
    QSet<QString> defs;      // the next word is a title (function or class)
    QStringList line;        // line comment openers
    QString open, close;     // block comment
    QString quotes = QStringLiteral("\"'");
    bool noCase = false;     // SQL, VB, DOS, KQL…
    bool markup = false;     // XML, HTML, JSX tags
    bool css = false;        // property: value
    bool jsonKeys = false;   // "key": → attr
    bool calls = false;      // name( is a function (hljs' title.function.invoke)
};

QSet<QString> words(const char *list)
{
    QSet<QString> out;
    for (const QString &w : QString::fromLatin1(list).split(QLatin1Char(' '), Qt::SkipEmptyParts))
        out.insert(w);
    return out;
}

const CodeLang *codeLang(const QString &id)
{
    static QHash<QString, CodeLang> langs;
    if (langs.isEmpty()) {
        const QStringList slash{QStringLiteral("//")}, hash{QStringLiteral("#")};
        const QString cOpen = QStringLiteral("/*"), cClose = QStringLiteral("*/");
        auto c_like = [&](const char *kw, const char *bi, const char *defs) {
            CodeLang l; l.keywords = words(kw); l.builtins = words(bi); l.defs = words(defs);
            l.line = slash; l.open = cOpen; l.close = cClose; return l;
        };
        const char *cKw = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool _Bool true false NULL #include #define #ifdef #ifndef #endif #if #else #pragma";
        langs[QStringLiteral("c")] = c_like(cKw, "printf malloc free memcpy strlen sizeof fprintf scanf puts", "struct enum union");
        langs[QStringLiteral("cpp")] = c_like((QByteArray(cKw) + " class namespace template typename public private protected virtual override final new delete this using try catch throw nullptr constexpr noexcept operator friend explicit mutable static_cast dynamic_cast reinterpret_cast const_cast decltype concept requires co_await co_return co_yield").constData(), "std cout cin endl string vector map set make_unique make_shared move printf", "class struct enum union namespace");
        langs[QStringLiteral("cpp")].calls = true;
        langs[QStringLiteral("objectivec")] = c_like((QByteArray(cKw) + " @interface @implementation @end @property @protocol @class self super nil YES NO id instancetype nonatomic strong weak readonly").constData(), "NSLog NSString NSArray NSDictionary NSObject alloc init", "@interface @implementation @protocol");
        langs[QStringLiteral("csharp")] = c_like("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await get set value yield record init", "Console WriteLine ToString Task List Dictionary Math String", "class struct interface enum record namespace void");
        langs[QStringLiteral("java")] = c_like("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record true false null", "System String Math Integer List ArrayList Map HashMap println", "class interface enum record");
        langs[QStringLiteral("jsp")] = langs[QStringLiteral("java")];
        const char *jsKw = "as async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch this throw try typeof var void while with yield true false null undefined";
        langs[QStringLiteral("javascript")] = c_like(jsKw, "console window document Math JSON Object Array Promise String Number require module exports parseInt setTimeout", "function class");
        langs[QStringLiteral("javascript")].quotes = QStringLiteral("\"'`");
        langs[QStringLiteral("javascript")].calls = true;
        langs[QStringLiteral("jsx")] = langs[QStringLiteral("javascript")];
        langs[QStringLiteral("jsx")].markup = true;
        langs[QStringLiteral("typescript")] = c_like((QByteArray(jsKw) + " type interface enum implements declare namespace abstract private public protected readonly keyof infer is any string number boolean unknown never void").constData(), "console window document Math JSON Object Array Promise String Number", "function class interface type enum");
        langs[QStringLiteral("typescript")].quotes = QStringLiteral("\"'`");
        langs[QStringLiteral("typescript")].calls = true;
        langs[QStringLiteral("go")] = c_like("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr true false iota nil", "append cap close complex copy delete imag len make new panic print println real recover fmt", "func type");
        langs[QStringLiteral("go")].quotes = QStringLiteral("\"'`");
        langs[QStringLiteral("rust")] = c_like("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Option Result Some None Ok Err Vec Box", "println! print! eprintln! format! vec! panic! assert! assert_eq! write! writeln! todo! unimplemented! matches!", "fn struct enum trait impl type mod union");
        langs[QStringLiteral("rust")].calls = true;
        langs[QStringLiteral("kotlin")] = c_like("abstract annotation as break by catch class companion const constructor continue crossinline data do else enum external false final finally for fun get if import in infix init inline inner interface internal is lateinit noinline null object open operator out override package private protected public reified return sealed set super suspend this throw true try typealias val var vararg when where while Int Long String Boolean Unit Any", "println print listOf mapOf setOf arrayOf require check", "fun class interface object");
        langs[QStringLiteral("scala")] = c_like("abstract case catch class def do else extends false final finally for forSome if implicit import lazy match new null object override package private protected return sealed super this throw trait try true type val var while with yield Int String Unit Boolean", "println print List Map Seq Option Some None", "def class trait object");
        langs[QStringLiteral("swift")] = c_like("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch false is nil super self Self throw throws true try Int String Bool Double Float Any", "print min max abs", "func class struct enum protocol extension");
        langs[QStringLiteral("dart")] = c_like("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for get if implements import in is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield int double String bool List Map", "print", "class enum mixin extension typedef");
        langs[QStringLiteral("php")] = c_like("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false null", "strlen count array_map json_encode explode implode", "function class interface trait");
        langs[QStringLiteral("php")].line = QStringList{QStringLiteral("//"), QStringLiteral("#")};
        CodeLang py; py.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield True False None");
        py.builtins = words("print len range int str float list dict set tuple open enumerate zip map filter sorted isinstance super type abs min max sum any all input");
        py.defs = words("def class"); py.line = hash;
        langs[QStringLiteral("python")] = py;
        CodeLang rb; rb.keywords = words("alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor");
        rb.builtins = words("puts print p raise lambda proc"); rb.defs = words("def class module"); rb.line = hash;
        langs[QStringLiteral("ruby")] = rb;
        CodeLang pl; pl.keywords = words("my our local sub if elsif else unless while until for foreach last next redo return use require package and or not eq ne lt gt le ge"); pl.builtins = words("print printf say push pop shift unshift split join keys values defined"); pl.defs = words("sub package"); pl.line = hash;
        langs[QStringLiteral("perl")] = pl;
        CodeLang sh; sh.keywords = words("if then else elif fi case esac for while until do done in function select time return exit export local readonly declare unset shift break continue");
        sh.builtins = words("echo printf cd pwd ls cat grep sed awk read source eval exec test set trap kill wait mkdir rm cp mv chmod sudo"); sh.defs = words("function"); sh.line = hash;
        langs[QStringLiteral("bash")] = sh; langs[QStringLiteral("shell")] = sh;
        CodeLang ps; ps.keywords = words("begin break catch class continue data define do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while -eq -ne -gt -lt -ge -le -like -match -and -or -not $true $false $null");
        ps.builtins = words("Write-Host Write-Output Get-Item Get-ChildItem Set-Item New-Object Get-Content Set-Content Where-Object ForEach-Object Select-Object"); ps.defs = words("function class filter"); ps.line = hash; ps.open = QStringLiteral("<#"); ps.close = QStringLiteral("#>"); ps.noCase = true;
        langs[QStringLiteral("powershell")] = ps;
        CodeLang dos; dos.keywords = words("if else goto for in do call exit not exist errorlevel defined equ neq lss leq gtr geq set setlocal endlocal shift"); dos.builtins = words("echo cd dir copy del md rd ren type cls pause start"); dos.line = QStringList{QStringLiteral("rem "), QStringLiteral("::")}; dos.noCase = true; dos.quotes = QStringLiteral("\"");
        langs[QStringLiteral("dos")] = dos;
        CodeLang sql; sql.keywords = words("select from where and or not insert into values update set delete create table alter drop index view join inner left right outer full on as group by order having limit offset union all distinct case when then else end is null like in between exists primary key foreign references default int integer varchar char text date datetime boolean decimal float begin commit rollback transaction with top asc desc");
        sql.builtins = words("count sum avg min max coalesce cast convert now getdate upper lower substring len length round"); sql.line = QStringList{QStringLiteral("--")}; sql.open = cOpen; sql.close = cClose; sql.noCase = true; sql.quotes = QStringLiteral("'\"");
        langs[QStringLiteral("sql")] = sql;
        CodeLang kql = sql; kql.keywords = words("let where project extend summarize by take top order sort asc desc join union on kind count distinct render as and or not in has contains startswith endswith between ago now datetime timespan bin"); kql.line = slash; kql.open.clear(); kql.close.clear(); kql.noCase = false;
        langs[QStringLiteral("kql")] = kql;
        CodeLang r; r.keywords = words("if else repeat while function for in next break TRUE FALSE NULL Inf NaN NA return"); r.builtins = words("print c list library require paste cat length data.frame matrix apply sapply lapply"); r.defs = words("function"); r.line = hash;
        langs[QStringLiteral("r")] = r;
        CodeLang oct; oct.keywords = words("break case catch continue do else elseif end end_try_catch endfor endfunction endif endwhile for function global if otherwise persistent return switch try until while"); oct.builtins = words("disp printf zeros ones size length plot sum max min abs"); oct.defs = words("function"); oct.line = QStringList{QStringLiteral("%"), QStringLiteral("#")}; oct.open = QStringLiteral("%{"); oct.close = QStringLiteral("%}");
        langs[QStringLiteral("octave")] = oct;
        CodeLang lisp; lisp.keywords = words("defun defmacro defvar defparameter let let* lambda if cond when unless progn setq setf loop do dolist quote and or not t nil"); lisp.builtins = words("car cdr cons list format print funcall apply mapcar"); lisp.defs = words("defun defmacro"); lisp.line = QStringList{QStringLiteral(";")}; lisp.open = QStringLiteral("#|"); lisp.close = QStringLiteral("|#"); lisp.quotes = QStringLiteral("\"");
        langs[QStringLiteral("lisp")] = lisp;
        CodeLang vb; vb.keywords = words("addhandler addressof alias and andalso as boolean byref byte byval call case catch cbool cbyte cchar cdate cdbl cdec char cint class clng cobj const continue csbyte cshort csng cstr ctype cuint culng cushort date decimal declare default delegate dim directcast do double each else elseif end endif enum erase error event exit false finally for friend function get gettype global gosub goto handles if implements imports in inherits integer interface is isnot let lib like long loop me mod module mustinherit mustoverride mybase myclass namespace narrowing new next not nothing notinheritable notoverridable object of on operator option optional or orelse overloads overridable overrides paramarray partial private property protected public raiseevent readonly redim rem removehandler resume return sbyte select set shadows shared short single static step stop string structure sub synclock then throw to true try trycast typeof uinteger ulong ushort using variant wend when while widening with withevents writeonly xor");
        vb.builtins = words("console writeline msgbox"); vb.defs = words("sub function class module structure"); vb.line = QStringList{QStringLiteral("'"), QStringLiteral("rem ")}; vb.noCase = true; vb.quotes = QStringLiteral("\"");
        langs[QStringLiteral("vbnet")] = vb; langs[QStringLiteral("vbscript")] = vb;
        CodeLang vlog; vlog.keywords = words("module endmodule input output inout wire reg logic always always_ff always_comb assign begin end if else case endcase for parameter localparam posedge negedge initial integer function endfunction task endtask generate endgenerate"); vlog.line = slash; vlog.open = cOpen; vlog.close = cClose; vlog.defs = words("module function task");
        langs[QStringLiteral("verilog")] = vlog;
        CodeLang vhdl; vhdl.keywords = words("library use entity is port in out inout end architecture of begin signal variable constant process if then else elsif case when others loop for generate component map std_logic std_logic_vector integer boolean downto to and or not xor"); vhdl.line = QStringList{QStringLiteral("--")}; vhdl.noCase = true; vhdl.quotes = QStringLiteral("\""); vhdl.defs = words("entity architecture process component function procedure");
        langs[QStringLiteral("vhdl")] = vhdl;
        CodeLang gql; gql.keywords = words("query mutation subscription fragment on type input enum interface union scalar schema extend implements directive true false null"); gql.line = hash; gql.defs = words("query mutation subscription fragment type input enum interface union scalar"); gql.quotes = QStringLiteral("\"");
        langs[QStringLiteral("graphql")] = gql;
        CodeLang docker; docker.keywords = words("FROM RUN CMD LABEL MAINTAINER EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS"); docker.line = hash; docker.noCase = true;
        langs[QStringLiteral("dockerfile")] = docker;
        CodeLang http; http.keywords = words("GET POST PUT PATCH DELETE HEAD OPTIONS HTTP/1.1 HTTP/2"); http.quotes.clear();
        langs[QStringLiteral("http")] = http;
        CodeLang yaml; yaml.keywords = words("true false null yes no on off"); yaml.line = hash; yaml.jsonKeys = true;
        langs[QStringLiteral("yaml")] = yaml;
        CodeLang json; json.jsonKeys = true; json.quotes = QStringLiteral("\"");
        langs[QStringLiteral("json")] = json;
        CodeLang xml; xml.markup = true; xml.open = QStringLiteral("<!--"); xml.close = QStringLiteral("-->"); xml.quotes = QStringLiteral("\"'");
        langs[QStringLiteral("xml")] = xml; langs[QStringLiteral("html")] = xml;
        CodeLang css; css.css = true; css.open = cOpen; css.close = cClose; css.keywords = words("@media @import @font-face @keyframes @supports @charset !important");
        langs[QStringLiteral("css")] = css;
        CodeLang scss = css; scss.line = slash; scss.keywords.unite(words("@mixin @include @extend @use @forward @if @else @each @for @function @return"));
        langs[QStringLiteral("scss")] = scss;
        CodeLang tex; tex.line = QStringList{QStringLiteral("%")}; tex.quotes.clear();
        langs[QStringLiteral("latex")] = tex;
        CodeLang md; md.quotes = QStringLiteral("`");
        langs[QStringLiteral("markdown")] = md;
    }
    auto it = langs.constFind(id);
    return it == langs.constEnd() ? nullptr : &*it;
}

// Teams' "Auto-detect language" (on for a new code block): the language
// the block's words point to most, as highlight.js' highlightAuto picks one
// ("let x = 1; // hi" stays Plain Text; a few lines of Rust become Rust;
// seen on winpc 2026-11-10). Each keyword or built-in scores by how few
// languages share it, so words only one language uses decide; nothing
// changes until one language clearly leads.
QString detectLanguage(const QString &code)
{
    static const QStringList ids = {
        QStringLiteral("bash"), QStringLiteral("c"), QStringLiteral("cpp"), QStringLiteral("csharp"), QStringLiteral("css"),
        QStringLiteral("dart"), QStringLiteral("dockerfile"), QStringLiteral("dos"), QStringLiteral("go"), QStringLiteral("graphql"),
        QStringLiteral("java"), QStringLiteral("javascript"), QStringLiteral("json"), QStringLiteral("kotlin"),
        QStringLiteral("lisp"), QStringLiteral("objectivec"), QStringLiteral("octave"), QStringLiteral("perl"), QStringLiteral("php"),
        QStringLiteral("powershell"), QStringLiteral("python"), QStringLiteral("r"), QStringLiteral("ruby"), QStringLiteral("rust"),
        QStringLiteral("scala"), QStringLiteral("scss"), QStringLiteral("sql"), QStringLiteral("swift"), QStringLiteral("typescript"),
        QStringLiteral("vbnet"), QStringLiteral("verilog"), QStringLiteral("vhdl"), QStringLiteral("xml"), QStringLiteral("yaml")};
    QHash<QString, int> shared; // word -> how many languages know it
    for (const QString &id : ids) {
        const CodeLang *l = codeLang(id);
        for (const QString &w : l->keywords)
            ++shared[l->noCase ? w.toLower() : w];
        for (const QString &w : l->builtins)
            ++shared[l->noCase ? w.toLower() : w];
    }
    QStringList tokens;
    QString cur;
    for (const QChar ch : code + QLatin1Char(' ')) {
        if (ch.isLetterOrNumber() || ch == QLatin1Char('_') || ch == QLatin1Char('!') || ch == QLatin1Char('@') || ch == QLatin1Char('#') || ch == QLatin1Char('$')) {
            cur += ch;
        } else {
            if (!cur.isEmpty())
                tokens << cur;
            cur.clear();
        }
    }
    QString best, second;
    double bestScore = 0, secondScore = 0;
    for (const QString &id : ids) {
        const CodeLang *l = codeLang(id);
        double score = 0;
        for (const QString &t : tokens) {
            const QString k = l->noCase ? t.toLower() : t;
            const bool hit = l->keywords.contains(k) || l->builtins.contains(k) || (l->noCase && (l->keywords.contains(t.toUpper()) || l->keywords.contains(t)));
            if (hit)
                score += 1.0 / qMax(1, shared.value(k, 1));
        }
        // Markup and data formats show by their shape.
        if (l->markup && code.contains(QLatin1String("</")))
            score += 2;
        if (id == u"json" && code.trimmed().startsWith(QLatin1Char('{')) && code.contains(QLatin1String("\":")))
            score += 2;
        if (l->css && code.contains(QLatin1Char('{')) && code.contains(QLatin1Char(':')) && code.contains(QLatin1Char(';')) && !code.contains(QLatin1Char('(')))
            score += 1;
        if (score > bestScore) {
            second = best; secondScore = bestScore;
            best = id; bestScore = score;
        } else if (score > secondScore) {
            second = id; secondScore = score;
        }
    }
    return bestScore >= 2.0 && bestScore >= secondScore * 1.5 ? best : QString();
}

class CodeHighlighter : public QSyntaxHighlighter
{
public:
    CodeHighlighter(QTextDocument *doc, QQuickItem *edit) : QSyntaxHighlighter(doc), m_edit(edit) {}

protected:
    void highlightBlock(const QString &text) override
    {
        setCurrentBlockState(0);
        const QTextBlockFormat bf = currentBlock().blockFormat();
        if (!bf.boolProperty(CodeBlockP))
            return;
        const CodeLang *lang = codeLang(bf.stringProperty(BlockLang));
        if (!lang)
            return;
        const bool dark = m_edit && m_edit->property("color").value<QColor>().lightness() > 128;
        const QColor str(dark ? "#54B054" : "#237B4B"), kw(dark ? "#7F85F5" : "#4F52B2"),
            fn(dark ? "#E37D80" : "#C4314B"), cm(dark ? "#ADADAD" : "#707070");
        auto paint = [&](int from, int len, const QColor &c) {
            QTextCharFormat f = format(from);
            f.setForeground(c);
            setFormat(from, len, f);
        };
        const int n = text.size();
        int i = 0;
        // Inside a block comment carried over from the line above.
        if (previousBlockState() == 1 && !lang->close.isEmpty()) {
            const int end = text.indexOf(lang->close);
            if (end < 0) {
                paint(0, n, cm);
                setCurrentBlockState(1);
                return;
            }
            paint(0, end + lang->close.size(), cm);
            i = end + lang->close.size();
        }
        bool nextIsTitle = false;
        bool inTag = false;
        while (i < n) {
            const QChar ch = text.at(i);
            const QStringView rest = QStringView(text).mid(i);
            if (!lang->open.isEmpty() && rest.startsWith(lang->open)) {
                const int end = text.indexOf(lang->close, i + lang->open.size());
                if (end < 0) {
                    paint(i, n - i, cm);
                    setCurrentBlockState(1);
                    return;
                }
                paint(i, end + lang->close.size() - i, cm);
                i = end + lang->close.size();
                continue;
            }
            bool lineComment = false;
            for (const QString &l : lang->line) {
                // "#" opens a comment only at a word boundary ("a#b" isn't).
                if (rest.startsWith(l, lang->noCase ? Qt::CaseInsensitive : Qt::CaseSensitive)
                    && (l.size() > 1 || i == 0 || !text.at(i - 1).isLetterOrNumber())) {
                    lineComment = true;
                    break;
                }
            }
            if (lineComment && !inTag) {
                paint(i, n - i, cm);
                return;
            }
            if (lang->quotes.contains(ch)) {
                int j = i + 1;
                while (j < n && text.at(j) != ch) {
                    if (text.at(j) == QLatin1Char('\\'))
                        ++j;
                    ++j;
                }
                const int end = qMin(j + 1, n);
                // A JSON / YAML key ("key":) is an attribute.
                int k = end;
                while (k < n && text.at(k).isSpace())
                    ++k;
                const bool key = lang->jsonKeys && k < n && text.at(k) == QLatin1Char(':');
                paint(i, end - i, key ? fn : str);
                i = end;
                continue;
            }
            if (lang->markup && ch == QLatin1Char('<')) {
                int j = i + 1;
                if (j < n && (text.at(j) == QLatin1Char('/') || text.at(j) == QLatin1Char('?') || text.at(j) == QLatin1Char('!')))
                    ++j;
                const int start = j;
                while (j < n && (text.at(j).isLetterOrNumber() || text.at(j) == QLatin1Char('-') || text.at(j) == QLatin1Char(':') || text.at(j) == QLatin1Char('.')))
                    ++j;
                if (j > start) {
                    paint(start, j - start, kw);
                    inTag = true;
                    i = j;
                    continue;
                }
            }
            if (inTag && ch == QLatin1Char('>')) {
                inTag = false;
                ++i;
                continue;
            }
            if (ch.isDigit() && (i == 0 || !(text.at(i - 1).isLetterOrNumber() || text.at(i - 1) == QLatin1Char('_')))) {
                int j = i + 1;
                while (j < n && (text.at(j).isLetterOrNumber() || text.at(j) == QLatin1Char('.') || text.at(j) == QLatin1Char('_')))
                    ++j;
                paint(i, j - i, str);
                i = j;
                continue;
            }
            const bool wordStart = ch.isLetter() || ch == QLatin1Char('_') || ch == QLatin1Char('$') || ch == QLatin1Char('@') || ch == QLatin1Char('#') || ch == QLatin1Char('-');
            if (wordStart && (ch != QLatin1Char('-') || lang->noCase)) {
                int j = i + 1;
                // Hyphens join words in CSS, markup and case-blind languages
                // (font-size, data-id, Write-Host, -eq).
                while (j < n && (text.at(j).isLetterOrNumber() || text.at(j) == QLatin1Char('_')
                                 || (text.at(j) == QLatin1Char('-') && (lang->css || lang->markup || lang->noCase))))
                    ++j;
                // Rust's macros and Ruby's predicates end in "!" / "?".
                if (j < n && (text.at(j) == QLatin1Char('!') || text.at(j) == QLatin1Char('?'))
                    && (lang->builtins.contains(text.mid(i, j - i + 1)) || lang->keywords.contains(text.mid(i, j - i + 1))))
                    ++j;
                const QString w = text.mid(i, j - i);
                const QString key = lang->noCase ? w.toLower() : w;
                auto has = [&](const QSet<QString> &set) {
                    return set.contains(key) || (lang->noCase && set.contains(w.toUpper())) || set.contains(w);
                };
                if (inTag) {
                    paint(i, j - i, fn); // an attribute
                } else if (lang->css) {
                    int k = j;
                    while (k < n && text.at(k).isSpace())
                        ++k;
                    if (has(lang->keywords))
                        paint(i, j - i, kw);
                    else if (k < n && text.at(k) == QLatin1Char(':') && text.indexOf(QLatin1Char('{')) < 0)
                        paint(i, j - i, fn); // a property
                } else if (nextIsTitle) {
                    paint(i, j - i, fn);
                    nextIsTitle = false;
                } else if (has(lang->keywords)) {
                    paint(i, j - i, kw);
                    nextIsTitle = has(lang->defs);
                } else if (has(lang->builtins)) {
                    paint(i, j - i, fn);
                } else if (lang->calls && j < n && text.at(j) == QLatin1Char('(')) {
                    paint(i, j - i, fn);
                } else if (lang->jsonKeys) {
                    int k = j;
                    while (k < n && text.at(k).isSpace())
                        ++k;
                    if (k < n && text.at(k) == QLatin1Char(':'))
                        paint(i, j - i, fn);
                }
                i = j;
                continue;
            }
            ++i;
        }
    }

private:
    QPointer<QQuickItem> m_edit;
};

QTextDocument *documentOf(void *helper)
{
    auto *item = static_cast<QQuickItem *>(helper);
    QQuickItem *edit = item ? item->parentItem() : nullptr;
    if (!edit)
        return nullptr;
    auto *qdoc = edit->property("textDocument").value<QQuickTextDocument *>();
    QTextDocument *doc = qdoc ? qdoc->textDocument() : nullptr;
    // Code blocks are coloured as Teams' compose colours them.
    if (doc && !doc->findChild<QSyntaxHighlighter *>(QString(), Qt::FindDirectChildrenOnly))
        new CodeHighlighter(doc, edit);
    return doc;
}

QString escaped(const QString &s)
{
    return s.toHtmlEscaped();
}

char *dup(const QString &s)
{
    const QByteArray b = s.toUtf8();
    char *out = static_cast<char *>(std::malloc(b.size() + 1));
    std::memcpy(out, b.constData(), b.size() + 1);
    return out;
}

// The selection a..b; empty, the word under it (as Word applies a format
// to the word the cursor is in).
QTextCursor selection(QTextDocument *doc, int a, int b)
{
    QTextCursor c(doc);
    c.setPosition(qBound(0, a, doc->characterCount() - 1));
    c.setPosition(qBound(0, b, doc->characterCount() - 1), QTextCursor::KeepAnchor);
    if (!c.hasSelection())
        c.select(QTextCursor::WordUnderCursor);
    return c;
}

QString colorHex(const QColor &c)
{
    return c.name(QColor::HexRgb).toUpper();
}

// One run of text with its character format, as clean inline HTML.
QString fragmentHtml(const QTextFragment &frag, bool plain = false)
{
    const QTextCharFormat f = frag.charFormat();
    if (f.isImageFormat()) {
        const QTextImageFormat img = f.toImageFormat();
        QString s = QStringLiteral("<img src=\"%1\"").arg(escaped(img.name()));
        if (img.width() > 0)
            s += QStringLiteral(" width=\"%1\"").arg(qRound(img.width()));
        if (img.height() > 0)
            s += QStringLiteral(" height=\"%1\"").arg(qRound(img.height()));
        return s + QStringLiteral(">");
    }
    QString text = escaped(frag.text());
    text.replace(QChar::LineSeparator, QStringLiteral("<br>"));
    text.replace(QChar(0x00A0), QStringLiteral("&nbsp;"));
    // A heading's own size and weight aren't text formats.
    const bool heading = f.boolProperty(HeadingWeight);
    if (f.boolProperty(InlineCode))
        text = QStringLiteral("<code>") + text + QStringLiteral("</code>");
    QStringList style;
    if (f.hasProperty(QTextFormat::BackgroundBrush) && f.background().style() != Qt::NoBrush && !f.boolProperty(InlineCode))
        style << QStringLiteral("background-color:") + colorHex(f.background().color());
    if (f.hasProperty(QTextFormat::ForegroundBrush) && f.foreground().style() != Qt::NoBrush && !f.isAnchor())
        style << QStringLiteral("color:") + colorHex(f.foreground().color());
    if (f.hasProperty(QTextFormat::FontPixelSize) && !heading && !plain)
        style << QStringLiteral("font-size:%1px").arg(f.intProperty(QTextFormat::FontPixelSize));
    if (!style.isEmpty())
        text = QStringLiteral("<span style=\"%1\">").arg(style.join(QStringLiteral("; "))) + text + QStringLiteral("</span>");
    if (f.fontStrikeOut())
        text = QStringLiteral("<s>") + text + QStringLiteral("</s>");
    if (f.fontUnderline() && !f.isAnchor())
        text = QStringLiteral("<u>") + text + QStringLiteral("</u>");
    if (f.fontItalic())
        text = QStringLiteral("<i>") + text + QStringLiteral("</i>");
    if (f.fontWeight() >= QFont::DemiBold && !heading)
        text = QStringLiteral("<b>") + text + QStringLiteral("</b>");
    if (f.isAnchor() && !f.anchorHref().isEmpty())
        text = QStringLiteral("<a href=\"%1\">").arg(escaped(f.anchorHref())) + text + QStringLiteral("</a>");
    return text;
}

QString blockInline(const QTextBlock &block)
{
    QString s;
    for (auto it = block.begin(); !it.atEnd(); ++it)
        if (it.fragment().isValid())
            s += fragmentHtml(it.fragment());
    return s;
}

QString blockHtml(const QTextBlock &block)
{
    const QTextBlockFormat bf = block.blockFormat();
    if (bf.boolProperty(RuleBlock))
        return QStringLiteral("<hr>");
    QString inner = blockInline(block);
    if (inner.isEmpty())
        inner = QStringLiteral("&nbsp;");
    const int h = bf.headingLevel();
    if (h >= 1 && h <= 3)
        return QStringLiteral("<h%1>%2</h%1>").arg(h).arg(inner);
    if (bf.indent() > 0)
        return QStringLiteral("<p style=\"margin-left:%1px\">%2</p>").arg(bf.indent() * 40).arg(inner);
    return QStringLiteral("<p>") + inner + QStringLiteral("</p>");
}

// Teams' compose table (CKEditor's, measured on winpc): collapsed 0.67 px
// #616161 borders, the box's full width, cells padded 0 5.
void styleTable(QTextTable *t)
{
    QTextTableFormat tf = t->format();
    // 0.67 CSS px, but at least one device pixel, as a browser draws it (a
    // thinner line can fall between pixel rows and vanish).
    const qreal dpr = QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->devicePixelRatio() : 1.0;
    tf.setBorder(qMax<qreal>(0.67, 1.0 / dpr));
    tf.setBorderBrush(QColor(0x61, 0x61, 0x61));
    tf.setBorderStyle(QTextFrameFormat::BorderStyle_Solid);
    tf.setBorderCollapse(true);
    tf.setCellSpacing(0);
    tf.setCellPadding(0);
    tf.setMargin(0);
    tf.setWidth(QTextLength(QTextLength::PercentageLength, 100));
    t->setFormat(tf);
    for (int r = 0; r < t->rows(); ++r)
        for (int col = 0; col < t->columns(); ++col) {
            QTextTableCell cell = t->cellAt(r, col);
            QTextTableCellFormat cf = cell.format().toTableCellFormat();
            cf.setLeftPadding(5);
            cf.setRightPadding(5);
            cf.setTopPadding(0);
            cf.setBottomPadding(0);
            cf.setVerticalAlignment(QTextCharFormat::AlignMiddle);
            cell.setFormat(cf);
        }
}

// A table as Teams' editor sends it: <table><tbody><tr><td><p>…</p></td>…
// (Teams' editor also puts CRLF between block tags; OST's messages leave
// those out everywhere, and Teams draws both alike).
QString tableHtml(QTextTable *t)
{
    const QString nl;
    QString out = QStringLiteral("<table>") + nl + QStringLiteral("<tbody>") + nl;
    for (int r = 0; r < t->rows(); ++r) {
        out += QStringLiteral("<tr>") + nl;
        for (int col = 0; col < t->columns(); ++col) {
            const QTextTableCell cell = t->cellAt(r, col);
            if (cell.row() != r || cell.column() != col)
                continue;
            out += QStringLiteral("<td>") + nl;
            QTextDocument *doc = t->document();
            for (QTextBlock b = doc->findBlock(cell.firstPosition()); b.isValid() && b.position() <= cell.lastPosition(); b = b.next())
                out += blockHtml(b) + nl;
            out += QStringLiteral("</td>") + nl;
        }
        out += QStringLiteral("</tr>") + nl;
    }
    return out + QStringLiteral("</tbody>") + nl + QStringLiteral("</table>");
}

// The document's blocks: lists grouped, quote runs as <blockquote>, code
// runs as Teams' code block, tables as Teams' table.
QString documentHtml(QTextDocument *doc)
{
    QString out;
    QTextList *openList = nullptr;
    bool inQuote = false;
    auto closeList = [&]() {
        if (openList) {
            out += openList->format().style() == QTextListFormat::ListDecimal ? QStringLiteral("</ol>") : QStringLiteral("</ul>");
            openList = nullptr;
        }
    };
    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
        if (QTextTable *t = QTextCursor(block).currentTable()) {
            closeList();
            if (inQuote) {
                out += QStringLiteral("</blockquote>");
                inQuote = false;
            }
            out += tableHtml(t);
            // On from the table's last cell (the loop steps past it).
            block = doc->findBlock(t->lastPosition());
            continue;
        }
        const QTextBlockFormat bf = block.blockFormat();
        if (bf.boolProperty(CodeBlockP)) {
            closeList();
            if (inQuote) {
                out += QStringLiteral("</blockquote>");
                inQuote = false;
            }
            QStringList lines;
            QString lang = bf.stringProperty(BlockLang);
            for (; block.isValid() && block.blockFormat().boolProperty(CodeBlockP); block = block.next())
                lines << escaped(block.text());
            if (lang.isEmpty())
                lang = QStringLiteral("plaintext");
            const QString id = QStringLiteral("codeBlockEditor-") + QUuid::createUuid().toString(QUuid::WithoutBraces);
            out += QStringLiteral("<p itemtype=\"http://schema.skype.com/CodeBlockEditor\" id=\"%1\">&nbsp;</p>"
                                  "<pre class=\"language-%2\" itemid=\"%1\"><code>%3</code></pre>")
                       .arg(id, lang, lines.join(QStringLiteral("\n")));
            if (!block.isValid())
                break;
        }
        const bool q = block.blockFormat().boolProperty(QuoteBlock);
        if (q != inQuote) {
            closeList();
            out += q ? QStringLiteral("<blockquote>") : QStringLiteral("</blockquote>");
            inQuote = q;
        }
        if (QTextList *list = block.textList()) {
            if (list != openList) {
                closeList();
                openList = list;
                out += list->format().style() == QTextListFormat::ListDecimal ? QStringLiteral("<ol>") : QStringLiteral("<ul>");
            }
            out += QStringLiteral("<li>") + blockInline(block) + QStringLiteral("</li>");
            continue;
        }
        closeList();
        out += blockHtml(block);
    }
    closeList();
    if (inQuote)
        out += QStringLiteral("</blockquote>");
    return out;
}

} // namespace

// Apply one of the formatting bar's commands to a..b.
extern "C" void ost_rich_apply(void *helper, int a, int b, const char *op_utf8, const char *arg_utf8)
{
    QTextDocument *doc = documentOf(helper);
    if (!doc)
        return;
    const QString op = QString::fromUtf8(op_utf8);
    const QString arg = QString::fromUtf8(arg_utf8);
    QTextCursor c = selection(doc, a, b);
    QTextCursor blocks(doc);
    blocks.setPosition(qMin(a, b));
    blocks.setPosition(qMax(a, b), QTextCursor::KeepAnchor);
    const QTextCharFormat here = c.charFormat();
    c.beginEditBlock();
    QTextCharFormat f;
    if (op == u"bold") {
        f.setFontWeight(here.fontWeight() >= QFont::DemiBold ? QFont::Normal : QFont::Bold);
        c.mergeCharFormat(f);
    } else if (op == u"italic") {
        f.setFontItalic(!here.fontItalic());
        c.mergeCharFormat(f);
    } else if (op == u"underline") {
        f.setFontUnderline(!here.fontUnderline());
        c.mergeCharFormat(f);
    } else if (op == u"strike") {
        f.setFontStrikeOut(!here.fontStrikeOut());
        c.mergeCharFormat(f);
    } else if (op == u"bg" || op == u"fg") {
        // Each run keeps its other formats.
        const int prop = op == u"bg" ? QTextFormat::BackgroundBrush : QTextFormat::ForegroundBrush;
        if (arg.isEmpty()) {
            QTextCursor run(doc);
            for (int p = c.selectionStart(); p < c.selectionEnd(); ++p) {
                run.setPosition(p);
                run.setPosition(p + 1, QTextCursor::KeepAnchor);
                QTextCharFormat cf = run.charFormat();
                cf.clearProperty(prop);
                run.setCharFormat(cf);
            }
        } else {
            f.setProperty(prop, QBrush(QColor(arg)));
            c.mergeCharFormat(f);
        }
    } else if (op == u"size") {
        QTextCursor run(doc);
        for (int p = c.selectionStart(); p < c.selectionEnd(); ++p) {
            run.setPosition(p);
            run.setPosition(p + 1, QTextCursor::KeepAnchor);
            QTextCharFormat cf = run.charFormat();
            if (arg.isEmpty())
                cf.clearProperty(QTextFormat::FontPixelSize);
            else
                cf.setProperty(QTextFormat::FontPixelSize, arg.toInt());
            run.setCharFormat(cf);
        }
    } else if (op == u"code") {
        const bool on = !here.boolProperty(InlineCode);
        QTextCursor run(doc);
        for (int p = c.selectionStart(); p < c.selectionEnd(); ++p) {
            run.setPosition(p);
            run.setPosition(p + 1, QTextCursor::KeepAnchor);
            QTextCharFormat cf = run.charFormat();
            if (on) {
                cf.setProperty(InlineCode, true);
                cf.setFontFamilies({QString::fromLatin1(Mono)});
                cf.setBackground(Qt::white);
            } else {
                cf.clearProperty(InlineCode);
                cf.clearProperty(QTextFormat::FontFamilies);
                cf.clearProperty(QTextFormat::BackgroundBrush);
            }
            run.setCharFormat(cf);
        }
    } else if (op == u"clear") {
        // Clear all formatting: keep links and mentions.
        QTextCursor run(doc);
        for (int p = c.selectionStart(); p < c.selectionEnd(); ++p) {
            run.setPosition(p);
            run.setPosition(p + 1, QTextCursor::KeepAnchor);
            const QTextCharFormat old = run.charFormat();
            if (old.isImageFormat())
                continue;
            QTextCharFormat cf;
            if (old.isAnchor()) {
                cf.setAnchor(true);
                cf.setAnchorHref(old.anchorHref());
                cf.setForeground(old.foreground());
            }
            run.setCharFormat(cf);
        }
        QTextBlockFormat bf;
        bf.setHeadingLevel(0);
        blocks.mergeBlockFormat(bf);
    } else if (op == u"heading") {
        const int level = arg.toInt();
        QTextBlockFormat bf;
        bf.setHeadingLevel(level);
        blocks.mergeBlockFormat(bf);
        // Teams' rich style sizes: Heading 1 18 light, 2 14 bold, 3 12 bold.
        QTextCursor whole(doc);
        whole.setPosition(blocks.selectionStart());
        whole.movePosition(QTextCursor::StartOfBlock);
        whole.setPosition(blocks.selectionEnd(), QTextCursor::KeepAnchor);
        whole.movePosition(QTextCursor::EndOfBlock, QTextCursor::KeepAnchor);
        QTextCharFormat hf;
        if (level == 1) {
            hf.setProperty(QTextFormat::FontPixelSize, 18);
            hf.setFontWeight(QFont::Light);
        } else if (level == 2) {
            hf.setProperty(QTextFormat::FontPixelSize, 14);
            hf.setFontWeight(QFont::Bold);
        } else if (level == 3) {
            hf.setProperty(QTextFormat::FontPixelSize, 12);
            hf.setFontWeight(QFont::Bold);
        } else {
            hf.setFontWeight(QFont::Normal);
        }
        // The heading's own weight isn't bold text.
        hf.setProperty(HeadingWeight, level >= 1);
        if (level == 0)
            hf.clearProperty(QTextFormat::FontPixelSize);
        whole.mergeCharFormat(hf);
        if (level == 0) {
            QTextCursor run(doc);
            for (int p = whole.selectionStart(); p < whole.selectionEnd(); ++p) {
                run.setPosition(p);
                run.setPosition(p + 1, QTextCursor::KeepAnchor);
                QTextCharFormat cf = run.charFormat();
                cf.clearProperty(QTextFormat::FontPixelSize);
                cf.clearProperty(HeadingWeight);
                run.setCharFormat(cf);
            }
        }
    } else if (op == u"indent" || op == u"outdent") {
        const int d = op == u"indent" ? 1 : -1;
        QTextBlock blk = doc->findBlock(blocks.selectionStart());
        const QTextBlock last = doc->findBlock(blocks.selectionEnd());
        while (blk.isValid()) {
            QTextCursor bc(blk);
            if (QTextList *list = blk.textList()) {
                QTextListFormat lf = list->format();
                lf.setIndent(qMax(1, lf.indent() + d));
                list->setFormat(lf);
            } else {
                QTextBlockFormat bf = blk.blockFormat();
                bf.setIndent(qMax(0, bf.indent() + d));
                bc.setBlockFormat(bf);
            }
            if (blk == last)
                break;
            blk = blk.next();
        }
    } else if (op == u"table") {
        // Insert table's grid: "{columns}x{rows}".
        const QStringList cr = arg.split(QLatin1Char('x'));
        const int cols = cr.value(0).toInt(), rows = cr.value(1).toInt();
        if (cols >= 1 && rows >= 1 && cols <= 7 && rows <= 5) {
            QTextCursor at(doc);
            at.setPosition(qMax(a, b));
            if (!at.currentTable()) {
                QTextTableFormat tf;
                QTextTable *t = at.insertTable(rows, cols, tf);
                styleTable(t);
            }
        }
    } else if (op.startsWith(u"table-")) {
        // Insert column or row ▸ / Delete column, row, or table ▸.
        QTextCursor at(doc);
        at.setPosition(qMax(a, b));
        if (QTextTable *t = at.currentTable()) {
            const QTextTableCell cell = t->cellAt(at);
            const int r = cell.row(), col = cell.column();
            if (op == u"table-col-right")
                t->insertColumns(col + 1, 1);
            else if (op == u"table-col-left")
                t->insertColumns(col, 1);
            else if (op == u"table-row-above")
                t->insertRows(r, 1);
            else if (op == u"table-row-below")
                t->insertRows(r + 1, 1);
            else if (op == u"table-del-col")
                t->removeColumns(col, 1); // the last one takes the table
            else if (op == u"table-del-row")
                t->removeRows(r, 1);
            else if (op == u"table-del")
                t->removeRows(0, t->rows());
            if (op.contains(u"col-") || op.contains(u"row-"))
                styleTable(t);
        }
    } else if (op == u"hr") {
        QTextCursor at(doc);
        at.setPosition(qMax(a, b));
        at.movePosition(QTextCursor::EndOfBlock);
        QTextBlockFormat rule;
        rule.setProperty(RuleBlock, true);
        rule.setProperty(QTextFormat::BlockTrailingHorizontalRulerWidth, QTextLength(QTextLength::PercentageLength, 100));
        at.insertBlock(rule);
        at.insertBlock(QTextBlockFormat());
    } else if (op == u"quote") {
        const bool on = !doc->findBlock(blocks.selectionStart()).blockFormat().boolProperty(QuoteBlock);
        QTextBlock blk = doc->findBlock(blocks.selectionStart());
        const QTextBlock last = doc->findBlock(blocks.selectionEnd());
        while (blk.isValid()) {
            QTextBlockFormat bf = blk.blockFormat();
            if (on)
                bf.setProperty(QuoteBlock, true);
            else
                bf.clearProperty(QuoteBlock);
            QTextCursor(blk).setBlockFormat(bf);
            if (blk == last)
                break;
            blk = blk.next();
        }
    } else if (op == u"codeblock") {
        // A code line under the current paragraph (or this one, if empty).
        QTextCursor at(doc);
        at.setPosition(qMax(a, b));
        QTextBlockFormat bf;
        bf.setProperty(CodeBlockP, true);
        bf.setProperty(BlockLang, QStringLiteral("plaintext"));
        bf.setProperty(CodeAuto, true);
        QTextCharFormat mono;
        mono.setFontFamilies({QString::fromLatin1(Mono)});
        mono.setProperty(QTextFormat::FontPixelSize, 14);
        if (at.block().text().isEmpty()) {
            at.setBlockFormat(bf);
            at.setBlockCharFormat(mono);
            at.setCharFormat(mono);
        } else {
            at.movePosition(QTextCursor::EndOfBlock);
            at.insertBlock(bf, mono);
        }
    } else if (op == u"ul" || op == u"ol") {
        const auto style = op == u"ol" ? QTextListFormat::ListDecimal : QTextListFormat::ListDisc;
        QTextList *list = doc->findBlock(blocks.selectionStart()).textList();
        if (list && list->format().style() == style) {
            // Out of the list.
            QTextBlock blk = doc->findBlock(blocks.selectionStart());
            const QTextBlock last = doc->findBlock(blocks.selectionEnd());
            while (blk.isValid()) {
                if (QTextList *l = blk.textList())
                    l->remove(blk);
                QTextBlockFormat bf = blk.blockFormat();
                bf.setIndent(0);
                QTextCursor(blk).setBlockFormat(bf);
                if (blk == last)
                    break;
                blk = blk.next();
            }
        } else if (list) {
            QTextListFormat lf = list->format();
            lf.setStyle(style);
            list->setFormat(lf);
        } else {
            QTextListFormat lf;
            lf.setStyle(style);
            blocks.createList(lf);
        }
    } else if (op == u"link") {
        // arg: the address, a tab, the text to show.
        const QString href = arg.section(QLatin1Char('\t'), 0, 0);
        QString text = arg.section(QLatin1Char('\t'), 1);
        QTextCursor at(doc);
        at.setPosition(qMin(a, b));
        at.setPosition(qMax(a, b), QTextCursor::KeepAnchor);
        if (text.isEmpty())
            text = at.hasSelection() ? at.selectedText() : href;
        QTextCharFormat lf = at.charFormat();
        lf.setAnchor(true);
        lf.setAnchorHref(href);
        lf.setForeground(QColor(0x4F, 0x52, 0xB2));
        at.insertText(text, lf);
        QTextCharFormat plain = lf;
        plain.setAnchor(false);
        plain.setAnchorHref(QString());
        plain.clearForeground();
        at.setCharFormat(plain);
    } else if (op == u"newblock") {
        // A new plain paragraph at the end (as Enter after the last line).
        QTextCursor at(doc);
        at.movePosition(QTextCursor::End);
        at.insertBlock(QTextBlockFormat(), QTextCharFormat());
    } else if (op == u"lang" || op == u"autolang") {
        // The whole code block takes the language (picking one ends
        // auto-detection), or turns Auto-detect language on or off.
        QTextBlock blk = doc->findBlock(blocks.selectionStart());
        while (blk.previous().isValid() && blk.previous().blockFormat().boolProperty(CodeBlockP))
            blk = blk.previous();
        for (; blk.isValid() && blk.blockFormat().boolProperty(CodeBlockP); blk = blk.next()) {
            QTextBlockFormat bf = blk.blockFormat();
            if (op == u"lang") {
                bf.setProperty(BlockLang, arg);
                bf.setProperty(CodeAuto, false);
            } else {
                bf.setProperty(CodeAuto, arg == u"1");
            }
            QTextCursor(blk).setBlockFormat(bf);
        }
    }
    normalize(doc);
    c.endEditBlock();
}

// What applies at `pos` (for the bar's pressed buttons and Rich style):
// JSON {bold, italic, underline, strike, code, heading, quote, codeBlock,
// lang, list ("ul"/"ol"/"")}.
extern "C" char *ost_rich_state(void *helper, int pos)
{
    QTextDocument *doc = documentOf(helper);
    if (!doc)
        return dup(QStringLiteral("{}"));
    QTextCursor c(doc);
    c.setPosition(qBound(0, pos, doc->characterCount() - 1));
    const QTextCharFormat f = c.charFormat();
    const QTextBlock blk = c.block();
    const bool code = blk.blockFormat().boolProperty(CodeBlockP);
    QString list;
    if (QTextList *l = blk.textList())
        list = l->format().style() == QTextListFormat::ListDecimal ? QStringLiteral("ol") : QStringLiteral("ul");
    const bool headingWeight = f.boolProperty(HeadingWeight);
    // In a table: the next and previous cells' starts (-1 past either end),
    // for Tab and Shift+Tab.
    QString table = QStringLiteral("false"), next = QStringLiteral("-1"), prev = QStringLiteral("-1");
    if (QTextTable *t = c.currentTable()) {
        const QTextTableCell cell = t->cellAt(c);
        const int i = cell.row() * t->columns() + cell.column();
        const int n = t->rows() * t->columns();
        table = QStringLiteral("true");
        if (i + 1 < n)
            next = QString::number(t->cellAt((i + 1) / t->columns(), (i + 1) % t->columns()).lastCursorPosition().position());
        if (i > 0)
            prev = QString::number(t->cellAt((i - 1) / t->columns(), (i - 1) % t->columns()).lastCursorPosition().position());
    }
    return dup(QStringLiteral("{\"table\":%12,\"nextCell\":%13,\"prevCell\":%14,\"empty\":%11,\"bold\":%1,\"italic\":%2,\"underline\":%3,\"strike\":%4,\"code\":%5,\"heading\":%6,\"quote\":%7,\"codeBlock\":%8,\"lang\":\"%9\",\"list\":\"%10\"}")
                   .arg(!headingWeight && f.fontWeight() >= QFont::DemiBold ? "true" : "false",
                        f.fontItalic() ? "true" : "false",
                        f.fontUnderline() && !f.isAnchor() ? "true" : "false",
                        f.fontStrikeOut() ? "true" : "false",
                        f.boolProperty(InlineCode) ? "true" : "false")
                   .arg(blk.blockFormat().headingLevel())
                   .arg(blk.blockFormat().boolProperty(QuoteBlock) ? "true" : "false",
                        code ? "true" : "false",
                        code ? blk.blockFormat().stringProperty(BlockLang) : QString(),
                        list)
                   .arg(blk.length() <= 1 ? "true" : "false")
                   .arg(table, next, prev));
}

// The document as clean HTML: p/h1-3/hr/blockquote/pre/ul/ol, b/i/u/s,
// spans with background-color, color and font-size (px), code, links and
// images. Free it with ost_rich_free.
extern "C" char *ost_rich_export(void *helper)
{
    QTextDocument *doc = documentOf(helper);
    if (!doc)
        return dup(QString());
    return dup(documentHtml(doc));
}

// The quote and code runs, for QML to draw Teams' box and card behind
// them: JSON [{kind: "quote"|"code", start, end, lang, lines}].
extern "C" char *ost_rich_regions(void *helper)
{
    QTextDocument *doc = documentOf(helper);
    if (!doc)
        return dup(QStringLiteral("[]"));
    QStringList parts;
    for (QTextBlock b = doc->begin(); b.isValid();) {
        const QTextBlockFormat f = b.blockFormat();
        const bool q = f.boolProperty(QuoteBlock), code = f.boolProperty(CodeBlockP);
        if (!q && !code) {
            b = b.next();
            continue;
        }
        const int mark = q ? QuoteBlock : CodeBlockP;
        const int start = b.position();
        int end = start, lines = 0;
        QString lang = f.stringProperty(BlockLang);
        const bool autoLang = code && f.boolProperty(CodeAuto);
        const QTextBlock first = b;
        QStringList text;
        for (; b.isValid() && b.blockFormat().boolProperty(mark); b = b.next()) {
            end = b.position() + qMax(0, b.length() - 1);
            text << b.text();
            ++lines;
        }
        if (autoLang) {
            const QString found = detectLanguage(text.join(QLatin1Char('\n')));
            if (!found.isEmpty() && found != lang) {
                lang = found;
                for (QTextBlock l = first; l.isValid() && l.blockFormat().boolProperty(CodeBlockP); l = l.next()) {
                    QTextBlockFormat lf = l.blockFormat();
                    lf.setProperty(BlockLang, found);
                    QTextCursor(l).setBlockFormat(lf);
                }
            }
        }
        parts << QStringLiteral("{\"kind\":\"%1\",\"start\":%2,\"end\":%3,\"lang\":\"%4\",\"lines\":%5,\"auto\":%6}")
                     .arg(q ? "quote" : "code").arg(start).arg(end).arg(lang).arg(lines).arg(autoLang ? "true" : "false");
    }
    return dup(QStringLiteral("[") + parts.join(QLatin1Char(',')) + QStringLiteral("]"));
}

extern "C" void ost_rich_free(char *s)
{
    std::free(s);
}
