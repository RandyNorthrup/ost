//! Make Teams' SVG pictures draw right in Qt.
//!
//! Some of Teams' template icons (Illustrator exports) clip a shape with
//! `<clipPath><use xlink:href="#shape"/></clipPath>`, the shape kept in
//! `<defs>` and the clip path outside it. Qt's SVG renderer draws such a
//! clip path's shape (black) over the picture. `for_qt` puts a copy of the
//! shape in the clip path in place of the `<use>`, drops `<defs>` blocks
//! that hold only shapes (which SVG never draws anyway) and puts the clip
//! path in `<defs>`, where Qt uses it as a clip (checked with Qt 6.10).

/// The picture rewritten for Qt, or None when it needs nothing (or isn't
/// an SVG).
pub fn for_qt(bytes: &[u8]) -> Option<Vec<u8>> {
    let text = std::str::from_utf8(bytes).ok()?;
    let head = text.trim_start();
    if !(head.starts_with("<?xml") || head.starts_with("<svg") || head.starts_with("<!--")) || !text.contains("<svg") {
        return None;
    }
    if !text.contains("<clipPath") {
        return None;
    }
    let mut out = text.to_string();
    let mut changed = false;
    // Each <use> inside a clip path.
    let mut from = 0;
    while let Some(start) = out[from..].find("<clipPath").map(|i| i + from) {
        let Some(end) = out[start..].find("</clipPath>").map(|i| i + start) else { break };
        let block = out[start..end].to_string();
        let mut new_block = block.clone();
        let mut pos = 0;
        while let Some(u) = new_block[pos..].find("<use").map(|i| i + pos) {
            let Some(close) = new_block[u..].find('>').map(|i| i + u + 1) else { break };
            let tag = new_block[u..close].to_string();
            let id = attr(&tag, "xlink:href").or_else(|| attr(&tag, "href")).and_then(|h| h.strip_prefix('#').map(str::to_string));
            match id.and_then(|id| element_with_id(&out, &id).map(|e| (id, e))) {
                Some((id, element)) => {
                    let copy = element.replacen(&format!("id=\"{id}\""), "", 1);
                    new_block.replace_range(u..close, &copy);
                    pos = u + copy.len();
                    changed = true;
                }
                None => pos = close,
            }
        }
        out.replace_range(start..end, &new_block);
        from = start + new_block.len();
    }
    // Drop <defs> that now hold only shapes.
    let mut from = 0;
    while let Some(start) = out[from..].find("<defs").map(|i| i + from) {
        let Some(end) = out[start..].find("</defs>").map(|i| i + start + "</defs>".len()) else { break };
        let block = &out[start..end];
        let keeps = ["<clipPath", "<linearGradient", "<radialGradient", "<pattern", "<mask", "<symbol", "<filter", "<style", "<marker"];
        if !changed || keeps.iter().any(|k| block.contains(k)) {
            from = end;
        } else {
            out.replace_range(start..end, "");
            from = start;
        }
    }
    // Qt draws a clip path's shape unless the clip path sits in <defs>.
    let mut from = 0;
    while let Some(start) = out[from..].find("<clipPath").map(|i| i + from) {
        let Some(end) = out[start..].find("</clipPath>").map(|i| i + start + "</clipPath>".len()) else { break };
        let opened = out[..start].matches("<defs").count();
        let closed = out[..start].matches("</defs>").count();
        if opened > closed {
            from = end;
        } else {
            let block = format!("<defs>{}</defs>", &out[start..end]);
            out.replace_range(start..end, &block);
            from = start + block.len();
            changed = true;
        }
    }
    changed.then(|| out.into_bytes())
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let key = format!("{name}=\"");
    let i = tag.find(&key)? + key.len();
    let j = tag[i..].find('"')? + i;
    Some(tag[i..j].to_string())
}

/// The element (a self-closing shape tag) with this id.
fn element_with_id(svg: &str, id: &str) -> Option<String> {
    let key = format!("id=\"{id}\"");
    let at = svg.find(&key)?;
    let start = svg[..at].rfind('<')?;
    let end = svg[at..].find("/>").map(|i| i + at + 2)?;
    // Only a single self-closing element.
    let tag = &svg[start..end];
    (!tag[1..].contains('<')).then(|| tag.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clip_path_uses_are_inlined_for_qt() {
        // Teams' incident_response.svg, shortened.
        let svg = r##"<?xml version="1.0" encoding="utf-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 56 56">
<g>
	<rect fill="#C3F2F4" width="56" height="56"/>
	<g>
		<defs>
			<polygon id="SVGID_1_" points="31.2319,15.0401 26.068,15.0401 18.388,41.5706 38.9119,41.5706 			"/>
		</defs>
		<clipPath id="SVGID_2_">
			<use xlink:href="#SVGID_1_"  overflow="visible"/>
		</clipPath>
		<rect x="18.2374" y="22.299" clip-path="url(#SVGID_2_)" fill="#F8F8FB" width="20.6745" height="4.433"/>
	</g>
</g>
</svg>"##;
        let fixed = String::from_utf8(for_qt(svg.as_bytes()).unwrap()).unwrap();
        assert!(!fixed.contains("<use"));
        assert!(!fixed.contains("id=\"SVGID_1_\""));
        assert!(fixed.contains("<defs><clipPath id=\"SVGID_2_\">\n\t\t\t<polygon  points=\"31.2319"));
        assert!(fixed.contains("</clipPath></defs>"));
        assert_eq!(fixed.matches("<defs").count(), 1);
        assert!(fixed.contains("clip-path=\"url(#SVGID_2_)\""));
        // A picture fixed before (its clip path outside <defs>) is fixed
        // again; one already right is left alone.
        let older = fixed.replace("<defs><clipPath", "<clipPath").replace("</clipPath></defs>", "</clipPath>");
        assert_eq!(String::from_utf8(for_qt(older.as_bytes()).unwrap()).unwrap(), fixed);
        assert!(for_qt(fixed.as_bytes()).is_none());
        // Pictures without that need nothing.
        assert!(for_qt(b"<svg viewBox=\"0 0 1 1\"><rect/></svg>").is_none());
        assert!(for_qt(b"\x89PNG").is_none());
    }
}
