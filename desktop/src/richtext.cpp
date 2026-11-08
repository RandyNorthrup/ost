// The compose box's rich text, as Teams' formatting bar edits it: formats
// applied to the QTextDocument behind a QML TextEdit (cxx-qt has no
// bindings for QTextCursor), and the document written out as the small,
// clean HTML OST turns into Teams' message HTML (src/api/messages.rs).
//
// The helper item (RichText, src/rich_text.rs) sits inside the TextEdit;
// every call finds the document through its parent.
#include <QtCore/QUuid>
#include <QtGui/QTextBlock>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtGui/QTextDocumentFragment>
#include <QtGui/QTextFrame>
#include <QtGui/QTextList>
#include <QtGui/QTextTable>
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

QTextDocument *documentOf(void *helper)
{
    auto *item = static_cast<QQuickItem *>(helper);
    QQuickItem *edit = item ? item->parentItem() : nullptr;
    if (!edit)
        return nullptr;
    auto *qdoc = edit->property("textDocument").value<QQuickTextDocument *>();
    return qdoc ? qdoc->textDocument() : nullptr;
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

// The document's blocks: lists grouped, quote runs as <blockquote>, code
// runs as Teams' code block.
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
    } else if (op == u"lang") {
        // The whole code block takes the language.
        QTextBlock blk = doc->findBlock(blocks.selectionStart());
        while (blk.previous().isValid() && blk.previous().blockFormat().boolProperty(CodeBlockP))
            blk = blk.previous();
        for (; blk.isValid() && blk.blockFormat().boolProperty(CodeBlockP); blk = blk.next()) {
            QTextBlockFormat bf = blk.blockFormat();
            bf.setProperty(BlockLang, arg);
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
    return dup(QStringLiteral("{\"empty\":%11,\"bold\":%1,\"italic\":%2,\"underline\":%3,\"strike\":%4,\"code\":%5,\"heading\":%6,\"quote\":%7,\"codeBlock\":%8,\"lang\":\"%9\",\"list\":\"%10\"}")
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
                   .arg(blk.length() <= 1 ? "true" : "false"));
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
        const QString lang = f.stringProperty(BlockLang);
        for (; b.isValid() && b.blockFormat().boolProperty(mark); b = b.next()) {
            end = b.position() + qMax(0, b.length() - 1);
            ++lines;
        }
        parts << QStringLiteral("{\"kind\":\"%1\",\"start\":%2,\"end\":%3,\"lang\":\"%4\",\"lines\":%5}")
                     .arg(q ? "quote" : "code").arg(start).arg(end).arg(lang).arg(lines);
    }
    return dup(QStringLiteral("[") + parts.join(QLatin1Char(',')) + QStringLiteral("]"));
}

extern "C" void ost_rich_free(char *s)
{
    std::free(s);
}
