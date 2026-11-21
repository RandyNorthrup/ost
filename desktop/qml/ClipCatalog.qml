import QtQuick

// The clip recorder's local effect catalogs, as Microsoft Stream's camera
// (OneCamera) lists them for Teams (its chunks 629.js boards, 630.js
// filters, 631.js frames; build odsp-web-prod_2026-10-30.005). Only the
// names and parameters are here: every picture is Microsoft's and is
// fetched from Stream's public CDN when shown.
QtObject {
    readonly property string cdn: "https://res.public.onecdn.static.microsoft/files/odsp-web-prod_2026-10-30.005/streamcameraembed/images/"
    function url(file) { return cdn + file }
    /// Filter: name, icon, exposure, contrast, twoTone (colorA to colorB),
    /// pixelate, lut {url, squares 16|64, ratio}, sprite {url, cols, rows,
    /// frames, fps, blend 0 ADD|1 SCREEN|2 MULTIPLY, opacity}, overlay
    /// {url, width, height, alpha}.
    readonly property var filters: [
        Object.assign({ name: qsTr("Lift") }, {"icon": "lut-lift-thumb-ls_6df43537.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-lift_1956de82.png", "squares": 64, "ratio": 1}}),
        Object.assign({ name: qsTr("Manifest") }, {"icon": "lut-manifest-thumb-ls_cfbc3266.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-manifest_7f25db6c.png", "squares": 16, "ratio": 1}, "sprite": {"url": "manifest_0_4997a343.jpg", "cols": 9, "rows": 8, "frames": 72, "fps": 24, "blend": 1, "opacity": 0.6}}),
        Object.assign({ name: qsTr("Vintage") }, {"icon": "lut-vintage-thumb-ls_352246b5.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-vintage_5d9dce51.png", "squares": 16, "ratio": 0.8}, "sprite": {"url": "vintage_0_bde3fc0d.png", "cols": 10, "rows": 5, "frames": 47, "fps": 23.5, "blend": 1, "opacity": 0.84}}),
        Object.assign({ name: qsTr("Memory") }, {"icon": "lut-memory-thumb-ls_65323c9b.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-memory_448d4223.png", "squares": 16, "ratio": 1}, "sprite": {"url": "memory_0_5676df9c.png", "cols": 11, "rows": 6, "frames": 61, "fps": 18, "blend": 1, "opacity": 0.9}}),
        Object.assign({ name: qsTr("Breeze") }, {"icon": "lut-breeze-thumb-ls_1f0fc0be.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-breeze_7f113e5d.png", "squares": 64, "ratio": 1}}),
        Object.assign({ name: qsTr("Dramatic") }, {"icon": "lut-dramatic-thumb-ls_e388a456.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-dramatic_eab32213.png", "squares": 64, "ratio": 1}}),
        Object.assign({ name: qsTr("Super") }, {"icon": "lut-super-thumb-ls_9781aa1b.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-super_5a32dc36.png", "squares": 64, "ratio": 1}}),
        Object.assign({ name: qsTr("Golden") }, {"icon": "lut-golden-thumb-ls_59a6257d.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-golden_88dae08d.png", "squares": 64, "ratio": 1}}),
        Object.assign({ name: qsTr("Magenta Dreams") }, {"icon": "lut-magenta-dreams-thumb-ls_23a0b7b7.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-magenta-dreams_ff83240f.png", "squares": 16, "ratio": 0.9}, "sprite": {"url": "dreams_0_addbea25.png", "cols": 12, "rows": 6, "frames": 70, "fps": 13.75, "blend": 0, "opacity": 0.18}}),
        Object.assign({ name: qsTr("Cyan Dreams") }, {"icon": "lut-cyan-dreams-thumb-ls_7e993c17.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-cyan-dreams_c2a0ef17.png", "squares": 16, "ratio": 0.9}, "sprite": {"url": "dreams_0_addbea25.png", "cols": 12, "rows": 6, "frames": 70, "fps": 13.75, "blend": 0, "opacity": 0.18}}),
        Object.assign({ name: qsTr("Scarlet Dreams") }, {"icon": "lut-scarlet-dreams-thumbs-ls_fa7ddc65.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-scarlet-dreams_df126a20.png", "squares": 16, "ratio": 0.9}, "sprite": {"url": "dreams_0_addbea25.png", "cols": 12, "rows": 6, "frames": 70, "fps": 13.75, "blend": 0, "opacity": 0.18}}),
        Object.assign({ name: qsTr("Laguna Dreams") }, {"icon": "lut-laguna-dreams-thumb-ls_7e40aa95.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-laguna-dreams_3be7ef74.png", "squares": 16, "ratio": 0.9}, "sprite": {"url": "dreams_0_addbea25.png", "cols": 12, "rows": 6, "frames": 70, "fps": 13.75, "blend": 0, "opacity": 0.18}}),
        Object.assign({ name: qsTr("Rainbow") }, {"icon": "lut-rainbow-thumb-ls_ace384df.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "overlay": {"url": "rainbow_7b0b6239.png", "width": 960, "height": 540, "alpha": true}}),
        Object.assign({ name: qsTr("Mystery") }, {"icon": "lut-mystery-thumb-ls_94f328a1.png", "exposure": 1, "contrast": 1, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": false, "lut": {"url": "lut-mystery_4c41a15a.jpg", "squares": 16, "ratio": 1}}),
        Object.assign({ name: qsTr("Black and White") }, {"icon": "lut-bw-thumb-ls_00c6f2cb.png", "exposure": 1.5, "contrast": 1.5, "twoTone": true, "colorA": "#000000", "colorB": "#FFFFFF", "pixelate": false}),
        Object.assign({ name: qsTr("Nightmode") }, {"icon": "lut-night-mode-thumb-ls_07148f7a.png", "exposure": 1.1, "contrast": 1.2, "twoTone": true, "colorA": "#000000", "colorB": "#FFFFFF", "pixelate": false}),
        Object.assign({ name: qsTr("Bricks") }, {"icon": "bricks_icon_landscape_cada0df2.png", "exposure": 1.1, "contrast": 1.3, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": true, "overlay": {"url": "dot_f1a01e71.png", "width": 32, "height": 32, "alpha": false}}),
        Object.assign({ name: qsTr("Pixelated") }, {"icon": "pixels_icon_landscape_f67a0594.png", "exposure": 1.1, "contrast": 1.3, "twoTone": false, "colorA": "#ffffff", "colorB": "#ffffff", "pixelate": true})
    ]
    /// Frame: a full-picture PNG laid over everything.
    readonly property var frames: [
        Object.assign({ name: qsTr("Frosted Glass") }, {"id": "Microsoft_Frames_frostedglass", "url": "frostedglass_7fad37c8.png", "icon": "frostedglass_210x118_5bf8d2cd.png"}),
        Object.assign({ name: qsTr("White Curves") }, {"id": "Microsoft_Frames_whitecurves", "url": "whitecurves_ae4a0978.png", "icon": "whitecurves_210x118_70616ea0.png"}),
        Object.assign({ name: qsTr("Frosted Blocks") }, {"id": "Microsoft_Frames_frostedblocks", "url": "frostedblocks_ae170a49.png", "icon": "frostedblocks_210x118_c933a9bf.png"}),
        Object.assign({ name: qsTr("Blue Bubbles") }, {"id": "Microsoft_Frames_bluebubbles", "url": "bluebubbles_638cb5b2.png", "icon": "bluebubbles_210x118_6f703065.png"}),
        Object.assign({ name: qsTr("Squiggles") }, {"id": "Microsoft_Frames_squiggles", "url": "squiggles_570c71a2.png", "icon": "squiggles_210x118_eeea94e0.png"}),
        Object.assign({ name: qsTr("Art Strokes") }, {"id": "Microsoft_Frames_artstrokes", "url": "artstrokes_0f8517bf.png", "icon": "artstrokes_210x118_c39451a7.png"}),
        Object.assign({ name: qsTr("Pola") }, {"id": "Microsoft_Frames_pola", "url": "pola_0ea55779.png", "icon": "pola_210x118_0aa00aca.png"}),
        Object.assign({ name: qsTr("Hi Fives") }, {"id": "Microsoft_Frames_hifives", "url": "hifives_8e83c007.png", "icon": "hifives_210x118_97e9b6f7.png"}),
        Object.assign({ name: qsTr("Geometric Fresh") }, {"id": "Microsoft_Frames_geometricfresh", "url": "geometricfresh_bde75c86.png", "icon": "geometric-fresh_210x118_186a71b1.png"}),
        Object.assign({ name: qsTr("Geometric Night") }, {"id": "Microsoft_Frames_geometricnight", "url": "geometricnight_d8f566a3.png", "icon": "geometric-night_210x118_51e62072.png"}),
        Object.assign({ name: qsTr("Update") }, {"id": "Microsoft_Frames_update", "url": "update_9457186f.png", "icon": "update_210x118_d1506101.png"}),
        Object.assign({ name: qsTr("Valentine's Day") }, {"id": "Microsoft_Frames_valentinesDay", "url": "valentinesday_landscape_232d4281.png", "icon": "valentinesday_icon_landscape_9ee4fc4f.png"}),
        Object.assign({ name: qsTr("Working Hard") }, {"id": "Microsoft_Frames_workingHard", "url": "office_landscape_f7356a25.png", "icon": "office_icon_landscape_381a699c.png"}),
        Object.assign({ name: qsTr("DJ") }, {"id": "Microsoft_Frames_dj", "url": "dj_landscape_081b7391.png", "icon": "dj_icon_landscape_ec4910ed.png"}),
        Object.assign({ name: qsTr("Festive Ribbons") }, {"id": "Microsoft_Frames_festiveRibbons", "url": "festiveribbons_landscape_eb3f13d5.png", "icon": "festiveribbons_icon_landscape_7ce5c9cb.png"}),
        Object.assign({ name: qsTr("Gift Box") }, {"id": "Microsoft_Frames_giftBox", "url": "giftbox_landscape_a9169856.png", "icon": "giftbox_icon_landscape_73a79418.png"}),
        Object.assign({ name: qsTr("Celebration") }, {"id": "Microsoft_Frames_celebration", "url": "celebration_landscape_89cb17bf.png", "icon": "celebration_icon_landscape_807f20a7.png"}),
        Object.assign({ name: qsTr("My Story") }, {"id": "Microsoft_Frames_myStory", "url": "my_story_landscape_edd37558.png", "icon": "my_story_icon_landscape_58e4c0df.png"}),
        Object.assign({ name: qsTr("Autumn") }, {"id": "Microsoft_Frames_autumn", "url": "autumn_landscape_342cfc3e.png", "icon": "autumn_icon_landscape_ab2bd634.png"}),
        Object.assign({ name: qsTr("Glitter") }, {"id": "Microsoft_Frames_glitter", "url": "goldglitter_icon_landscape_f04ff2ee.png", "icon": "goldglitter_icon_landscape_f04ff2ee.png"}),
        Object.assign({ name: qsTr("Winter") }, {"id": "Microsoft_Frames_winter", "url": "winter_landscape_d6491c49.png", "icon": "winter_icon_landscape_dd03ff52.png"}),
        Object.assign({ name: qsTr("Spring") }, {"id": "Microsoft_Frames_spring", "url": "spring_landscape_99d928e1.png", "icon": "spring_icon_landscape_93b26cdc.png"}),
        Object.assign({ name: qsTr("Summer") }, {"id": "Microsoft_Frames_summer", "url": "summer_landscape_8f3dbf7d.png", "icon": "summer_icon_landscape_fd747a72.png"}),
        Object.assign({ name: qsTr("Neon Purple") }, {"id": "Microsoft_Frames_neonPurple", "url": "neon_purple_landscape_b62d2300.png", "icon": "neon_purple_icon_landscape_4ed5ec9f.png"}),
        Object.assign({ name: qsTr("Flowers") }, {"id": "Microsoft_Frames_flowers", "url": "flowers_landscape_9c28ecc7.png", "icon": "flowers_icon_landscape_1bf9a0f1.png"}),
        Object.assign({ name: qsTr("Paint") }, {"id": "Microsoft_Frames_paint", "url": "paint_landscape_d81db754.png", "icon": "paint_icon_landscape_fde2124e.png"}),
        Object.assign({ name: qsTr("Bokeh") }, {"id": "Microsoft_Frames_bokeh", "url": "bokeheffect_landscape_4cdfcd1b.png", "icon": "bokeheffect_icon_landscape_122cfece.png"}),
        Object.assign({ name: qsTr("New Report") }, {"id": "Microsoft_Frames_newsReport", "url": "news_landscape_2c66546f.png", "icon": "news_icon_landscape_61456a2d.png"}),
        Object.assign({ name: qsTr("Retro") }, {"id": "Microsoft_Frames_retro", "url": "retro_landscape_8a8f4164.png", "icon": "retro_icon_landscape_755b5072.png"}),
        Object.assign({ name: qsTr("Underwater") }, {"id": "Microsoft_Frames_underwater", "url": "underwater_landscape_992bdab7.png", "icon": "underwater_icon_landscape_0904e2a7.png"}),
        Object.assign({ name: qsTr("Jungle") }, {"id": "Microsoft_Frames_jungle", "url": "jungle_landscape_3b4c57bd.png", "icon": "jungle_icon_landscape_569ddc93.png"})
    ]
    /// Board: a 16:9 picture that takes the right part of a split screen.
    readonly property var boards: [
        Object.assign({ name: qsTr("Minimal Grid") }, {"id": "effects.boards.minimalgrid", "url": "minimal_grid_landscape_d33a2194.jpg", "icon": "minimal_grid_icon_landscape_aa907c68.png"}),
        Object.assign({ name: qsTr("Design Grid") }, {"id": "effects.boards.designgrid", "url": "design_grid_landscape_fba89452.jpg", "icon": "design_grid_icon_landscape_09201044.png"}),
        Object.assign({ name: qsTr("Fresh Stickies") }, {"id": "effects.boards.freshstickies", "url": "fresh_stickies_landscape_6ac392b6.jpg", "icon": "fresh_stickies_icon_landscape_5a9bde67.png"}),
        Object.assign({ name: qsTr("White Dots") }, {"id": "effects.boards.whitedots", "url": "white_dots_landscape_09b3423b.jpg", "icon": "white_dots_icon_landscape_288a834e.png"}),
        Object.assign({ name: qsTr("Color Dots") }, {"id": "effects.boards.colordots", "url": "color_dots_landscape_6d5b80b2.jpg", "icon": "color_dots_icon_landscape_d8dd696b.png"}),
        Object.assign({ name: qsTr("Pink Dots") }, {"id": "effects.boards.pinkdots", "url": "pink_dots_landscape_6c5206e5.jpg", "icon": "pink_dots_icon_landscape_ac951b17.png"}),
        Object.assign({ name: qsTr("Dreamy Notepad") }, {"id": "effects.boards.dreamynotepad", "url": "dreamy_notepad_landscape_4d90d421.jpg", "icon": "dreamy_notepad_icon_landscape_752662ce.png"}),
        Object.assign({ name: qsTr("Dot Grid") }, {"id": "effects.boards.dotgrid", "url": "dots_landscape_9ccae443.png", "icon": "dots_icon_landscape_c35f414e.png"}),
        Object.assign({ name: qsTr("Graph") }, {"id": "effects.boards.graph", "url": "graph_landscape_fc3978d1.png", "icon": "graph_icon_landscape_7e8a1d55.png"}),
        Object.assign({ name: qsTr("Notebook") }, {"id": "effects.boards.notebook", "url": "notebook_landscape_e1b3f0a7.png", "icon": "notebook_icon_landscape_8a4364c4.png"}),
        Object.assign({ name: qsTr("Galaxy") }, {"id": "effects.boards.galaxy", "url": "galaxy_landscape_d3af9828.png", "icon": "galaxy_icon_landscape_a5121001.png"}),
        Object.assign({ name: qsTr("Whiteboard") }, {"id": "effects.boards.whiteboard", "url": "whiteboard_landscape_5e336600.png", "icon": "whiteboard_icon_landscape_47c6b1d2.png"}),
        Object.assign({ name: qsTr("Blackboard") }, {"id": "effects.boards.blackboard", "url": "blackboard_landscape_42ce9b9c.png", "icon": "blackboard_icon_landscape_244d2326.png"}),
        Object.assign({ name: qsTr("Chalkboard") }, {"id": "effects.boards.chalkboard", "url": "greenboard_landscape_aa55edeb.png", "icon": "greenboard_icon_landscape_8a10e554.png"}),
        Object.assign({ name: qsTr("Rainbow") }, {"id": "effects.boards.rainbow", "url": "gradient_rainbow_landscape_531339f8.png", "icon": "gradient_rainbow_icon_landscape_ae30fb9c.png"}),
        Object.assign({ name: qsTr("Vaporwave") }, {"id": "effects.boards.vaporwave", "url": "gradient_vaporwave_landscape_236e15df.png", "icon": "gradient_vaporwave_icon_landscape_125afeae.png"})
    ]
}
