//! Presenter modes (Teams' "advanced presenter layouts"): Standout
//! (`Weatherperson`), Side-by-side (`SideBySide`) and Reporter
//! (`NewsAnchor`). The presenter publishes a "weatherPerson" state with its
//! layout and keeps sending its screen and camera; each receiver
//! composites the camera over (or beside) the screen. This is Teams'
//! receiver arithmetic (WeatherpersonMixin, module 616836, read
//! 2026-11-16) with the production ECS values (`aplPositioningConfig`,
//! `weatherpersonPresenterSize`).

use serde::{Deserialize, Serialize};

/// A presenter mode, by Teams' names.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum Mode {
    #[default]
    ContentOnly,
    /// Standout: you over the content's bottom right corner.
    Weatherperson,
    SideBySide,
    /// Reporter: the content at the top left, you at the bottom right.
    NewsAnchor,
}

impl Mode {
    pub fn parse(s: &str) -> Self {
        match s {
            "Weatherperson" => Self::Weatherperson,
            "SideBySide" => Self::SideBySide,
            "NewsAnchor" => Self::NewsAnchor,
            _ => Self::ContentOnly,
        }
    }

    /// The camera is sent with its background cut out (Teams'
    /// doesModeNeedWeatherpersonEffectOnVideo).
    pub fn cuts_background(self) -> bool {
        matches!(self, Self::Weatherperson | Self::NewsAnchor)
    }

    /// Teams' isCustomBackgroundSupported: Add background applies.
    pub fn takes_background(self) -> bool {
        matches!(self, Self::SideBySide | Self::NewsAnchor)
    }
}

/// Teams' production positioning values.
pub mod config {
    pub const WP_PRESENTER_SIZE: f64 = 0.5;
    pub const SBS_GAP: f64 = 0.0225;
    pub const SBS_MAX_CONTENT_WIDTH: f64 = 0.66;
    pub const SBS_MAX_HEIGHT: f64 = 0.65;
    pub const SBS_MARGIN: f64 = 0.025;
    pub const SBS_MAX_PRESENTER_ASPECT: f64 = 0.75;
    pub const NA_CONTENT_LEFT_MARGIN: f64 = 0.025;
    pub const NA_CONTENT_MAX_HEIGHT: f64 = 0.65;
    pub const NA_CONTENT_MAX_WIDTH: f64 = 0.6;
    /// The content's aspect before its video size is known (`te`).
    pub const DEFAULT_CONTENT_ASPECT: f64 = 1.77;
    /// The camera's before its video size is known.
    pub const DEFAULT_PRESENTER_ASPECT: f64 = 1.333;
}

/// A box in fractions of the stage (x, y from the top left).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct Area {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// The layout a presenter publishes (Teams' `content` of the state).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Published {
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub x: f64,
    #[serde(default)]
    pub y: f64,
    #[serde(default)]
    pub width: f64,
    #[serde(default)]
    pub height: f64,
    #[serde(default)]
    pub z_order: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub background: Option<Background>,
}

/// An Add background picture (`{id, url, name}`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Background {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub name: String,
}

impl Published {
    pub fn mode(&self) -> Mode {
        Mode::parse(&self.mode)
    }

    /// What Teams publishes when you pick `mode` (getInitialLayoutStateConfig,
    /// zOrder 2), with the background for the modes that take one.
    pub fn initial(mode: Mode, background: Option<Background>) -> Self {
        let (x, y, width, height) = match mode {
            Mode::Weatherperson => {
                let s = config::WP_PRESENTER_SIZE;
                (1.0 - s, 1.0 - s, s, s)
            }
            Mode::SideBySide => (0.0, 0.0, config::SBS_MAX_CONTENT_WIDTH, config::SBS_MAX_HEIGHT),
            Mode::NewsAnchor => (0.0, 0.0, config::NA_CONTENT_MAX_WIDTH, config::NA_CONTENT_MAX_HEIGHT),
            Mode::ContentOnly => (0.0, 0.0, 1.0, 1.0),
        };
        let mode_name = match mode {
            Mode::Weatherperson => "Weatherperson",
            Mode::SideBySide => "SideBySide",
            Mode::NewsAnchor => "NewsAnchor",
            Mode::ContentOnly => "ContentOnly",
        };
        Self {
            mode: mode_name.into(),
            x,
            y,
            width,
            height,
            z_order: 2,
            background: background.filter(|_| mode.takes_background()),
        }
    }

    /// The content flipped to the right (Teams' isContentFlipped).
    fn flipped(&self) -> bool {
        self.width > 0.0 && self.x == 1.0
    }
}

/// Where the receiver draws everything, in fractions of its stage.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Composite {
    /// The shared screen's box (it is fitted inside, letterboxed).
    pub content: Area,
    /// The presenter's camera box.
    pub presenter: Area,
    /// Fill the presenter's box and crop (Side-by-side, Reporter), or fit
    /// inside it (Standout).
    pub crop: bool,
    /// The camera's background is cut out (Standout, Reporter).
    pub alpha: bool,
}

/// The shared screen's fitted size and margins inside the stage, in pixels
/// (Teams' getScaledSizeOfSharingContent).
struct Scaled {
    w: f64,
    h: f64,
    x_margin: f64,
    y_margin: f64,
}

fn scaled(mode: Mode, p: &Published, stage: (f64, f64), content_aspect: f64) -> Scaled {
    let (sw, sh) = stage;
    let margins = sw * config::SBS_MARGIN * 2.0;
    let gap = sw * config::SBS_GAP;
    let or = |v: f64, d: f64| if v > 0.0 { v } else { d };
    let (r, n) = match mode {
        Mode::SideBySide => (sw * or(p.width, config::SBS_MAX_CONTENT_WIDTH) - margins - gap, sh * or(p.height, config::SBS_MAX_HEIGHT)),
        Mode::NewsAnchor => (sw * or(p.width, config::NA_CONTENT_MAX_WIDTH), sh * or(p.height, config::NA_CONTENT_MAX_HEIGHT)),
        _ => (sw, sh),
    };
    let (mut w, mut h) = (r, n);
    if content_aspect > r / n {
        h = r / content_aspect;
    } else {
        w = n * content_aspect;
    }
    let mut x_margin = (r - w) / 2.0;
    let y_margin = (n - h) / 2.0;
    if mode == Mode::SideBySide {
        let rest = sw - x_margin * 2.0 - margins - w - gap;
        if rest / h > config::SBS_MAX_PRESENTER_ASPECT {
            x_margin += (rest - h * config::SBS_MAX_PRESENTER_ASPECT) / 2.0;
        }
    }
    Scaled { w, h, x_margin, y_margin }
}

/// Lay out a presenter's mode on a `stage` (pixels) for a shared screen of
/// `content_aspect` (width / height; None before its first frame) and a
/// camera of `presenter_aspect`.
pub fn composite(p: &Published, stage: (f64, f64), content_aspect: Option<f64>, presenter_aspect: Option<f64>) -> Composite {
    let mode = p.mode();
    let (sw, sh) = stage;
    let aspect = content_aspect.filter(|a| *a > 0.0).unwrap_or(config::DEFAULT_CONTENT_ASPECT);
    let s = scaled(mode, p, stage, aspect);
    // The content's box (getSharingLayoutAreaData).
    let mut content = Area { x: 0.0, y: 0.0, width: 1.0, height: 1.0 };
    match mode {
        Mode::SideBySide => {
            content.width = s.w / sw;
            content.height = s.h / sh;
            content.x = if p.flipped() {
                1.0 - (s.x_margin / sw + config::SBS_MARGIN + content.width)
            } else {
                s.x_margin / sw + config::SBS_MARGIN
            };
            content.y = (sh - s.h) / 2.0 / sh;
        }
        Mode::NewsAnchor => {
            content.width = s.w / sw;
            content.height = s.h / sh;
            content.x = if p.flipped() {
                1.0 - (config::NA_CONTENT_LEFT_MARGIN + content.width)
            } else {
                config::NA_CONTENT_LEFT_MARGIN
            };
            content.y = (1.0 - content.height) / 2.0;
        }
        _ => {}
    }
    // The presenter's box (getTransformedParticipantArea).
    let presenter = match mode {
        Mode::Weatherperson => {
            // Their box in the fitted content, sized by the camera's aspect.
            let r = presenter_aspect.filter(|a| *a > 0.0).unwrap_or(config::DEFAULT_PRESENTER_ASPECT);
            let size = config::WP_PRESENTER_SIZE;
            let layout = if p.width > 0.0 { (p.x, p.width, p.height) } else { (1.0 - size, size, size) };
            let (w, h) = if s.w < s.h {
                let w = layout.1;
                (w, w * s.w / (r * s.h))
            } else {
                let h = layout.2;
                (h * s.h * r / s.w, h)
            };
            let x = if p.width > 0.0 && layout.0 == 0.0 { 0.0 } else { 1.0 - w };
            let y = 1.0 - h;
            Area {
                x: (s.x_margin + s.w * x) / sw,
                y: (s.y_margin + s.h * y) / sh,
                width: w * s.w / sw,
                height: h * s.h / sh,
            }
        }
        Mode::SideBySide => {
            let x = if p.flipped() {
                s.x_margin / sw + config::SBS_MARGIN
            } else {
                (s.x_margin + s.w) / sw + config::SBS_MARGIN + config::SBS_GAP
            };
            let width = 1.0 - (s.x_margin * 2.0 + s.w) / sw - config::SBS_MARGIN * 2.0 - config::SBS_GAP;
            // getSideBySidePresenterHeight.
            let height = if p.height <= 0.0 || p.height <= config::SBS_MAX_HEIGHT {
                s.h / sh
            } else {
                let px = width * sw;
                if px / s.h >= config::SBS_MAX_PRESENTER_ASPECT {
                    s.h / sh
                } else {
                    px / config::SBS_MAX_PRESENTER_ASPECT / sh
                }
            };
            Area { x, y: (1.0 - height) / 2.0, width, height }
        }
        Mode::NewsAnchor => {
            // getNewsAnchorPresenterPosition: Y −2, Z 2.2, _ 1.45, ee 0.3.
            let t = if p.width > 0.0 { p.width } else { config::NA_CONTENT_MAX_WIDTH };
            let i = if p.height > 0.0 { p.height } else { config::NA_CONTENT_MAX_HEIGHT };
            let (max_w, max_h, cropped) = (t * -2.0 + 2.2, -i + 1.45, t - 0.3);
            Area {
                x: if p.flipped() { 1.0 - max_w - cropped } else { cropped },
                y: 1.0 - max_h,
                width: max_w,
                height: max_h,
            }
        }
        Mode::ContentOnly => Area::default(),
    };
    Composite {
        content,
        presenter,
        crop: mode != Mode::Weatherperson,
        alpha: mode != Mode::SideBySide,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    #[test]
    fn standout_puts_you_at_the_contents_bottom_right() {
        let p = Published::initial(Mode::Weatherperson, None);
        assert_eq!((p.x, p.y, p.width, p.height, p.z_order), (0.5, 0.5, 0.5, 0.5, 2));
        // A 16:9 screen on a 16:9 stage: the whole stage; you're half its
        // height, 4:3.
        let c = composite(&p, (1600.0, 900.0), Some(16.0 / 9.0), Some(4.0 / 3.0));
        assert!(close(c.content.width, 1.0) && close(c.content.x, 0.0));
        assert!(close(c.presenter.height, 0.5));
        assert!(close(c.presenter.width, 0.5 * 900.0 * (4.0 / 3.0) / 1600.0));
        assert!(close(c.presenter.x + c.presenter.width, 1.0) && close(c.presenter.y, 0.5));
        assert!(!c.crop && c.alpha);
        // A 4:3 screen letterboxed: you stay inside it.
        let c = composite(&p, (1600.0, 900.0), Some(4.0 / 3.0), Some(4.0 / 3.0));
        let right = (1600.0 - 1200.0) / 2.0 + 1200.0;
        assert!(close((c.presenter.x + c.presenter.width) * 1600.0, right));
    }

    #[test]
    fn reporter_and_side_by_side_follow_teams_numbers() {
        let na = Published::initial(Mode::NewsAnchor, None);
        let c = composite(&na, (1600.0, 900.0), Some(16.0 / 9.0), None);
        // Teams' presenter box (0.3, 0.2, 1.0, 0.8), cropped, cut out.
        assert_eq!(c.presenter.round(), Area { x: 0.3, y: 0.2, width: 1.0, height: 0.8 });
        assert!(close(c.content.x, 0.025) && close(c.content.width, 0.6) && c.crop && c.alpha);
        assert!(close(c.content.y, (1.0 - c.content.height) / 2.0));
        let sbs = Published::initial(Mode::SideBySide, None);
        let c = composite(&sbs, (1600.0, 900.0), Some(16.0 / 9.0), None);
        assert!(c.crop && !c.alpha);
        assert!(c.content.x >= 0.025 && c.presenter.x > c.content.x + c.content.width);
        assert!(close(c.presenter.height, c.content.height), "as tall as the content");
        assert!(c.presenter.width * 1600.0 / (c.presenter.height * 900.0) <= 0.75 + 1e-6, "no wider than 3:4");
        assert!(c.presenter.x + c.presenter.width <= 1.0 + 1e-9);
    }

    #[test]
    fn teams_published_layouts_parse() {
        let p: Published = serde_json::from_str(r#"{"mode":"NewsAnchor","x":0,"y":0,"width":0.6,"height":0.65,"zOrder":2,"background":{"id":"aplBackground_003","url":"/evergreen-assets/backgroundimages/aplBackground_003.jpg?v=0.1","name":""}}"#).unwrap();
        assert_eq!(p.mode(), Mode::NewsAnchor);
        assert_eq!(p.background.unwrap().id, "aplBackground_003");
        let s = serde_json::to_value(Published::initial(Mode::SideBySide, Some(Background { id: "b".into(), ..Default::default() }))).unwrap();
        assert_eq!(s["mode"], "SideBySide");
        assert_eq!(s["zOrder"], 2);
        assert_eq!(s["background"]["id"], "b");
        let w = serde_json::to_value(Published::initial(Mode::Weatherperson, Some(Background::default()))).unwrap();
        assert!(w.get("background").is_none(), "Standout takes no background");
    }

    impl Area {
        fn round(self) -> Self {
            let r = |v: f64| (v * 1e6).round() / 1e6;
            Self { x: r(self.x), y: r(self.y), width: r(self.width), height: r(self.height) }
        }
    }
}
