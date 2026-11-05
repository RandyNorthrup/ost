import QtQuick
import QtQuick.Controls.Basic

// The compose box's emoji picker: search, categories, a grid, and your
// recently used emoji first.
Popup {
    id: root
    signal picked(string emoji)
    width: 360; height: 380
    padding: 0
    property string query: ""
    property var recent: []
    background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }

    // [emoji, search words] by category, in Teams' order.
    readonly property var categories: [
        { name: "Smilies", icon: "😀", items: [
            ["😀","grin smile happy"],["😃","smile happy"],["😄","laugh smile"],["😁","grin beam"],["😆","laugh"],["😅","sweat laugh"],["🤣","rofl laugh"],["😂","joy tears laugh"],
            ["🙂","slight smile"],["🙃","upside down"],["😉","wink"],["😊","blush smile"],["😇","angel halo"],["🥰","love hearts"],["😍","heart eyes love"],["🤩","star struck"],
            ["😘","kiss"],["😗","kiss"],["😚","kiss"],["😋","yum tasty"],["😛","tongue"],["😜","wink tongue"],["🤪","zany crazy"],["😝","tongue"],
            ["🤑","money"],["🤗","hug"],["🤭","oops hand"],["🤫","shush quiet"],["🤔","thinking"],["🤐","zipper"],["🤨","raised eyebrow"],["😐","neutral"],
            ["😑","expressionless"],["😶","no mouth"],["😏","smirk"],["😒","unamused"],["🙄","eye roll"],["😬","grimace"],["😌","relieved"],["😔","pensive sad"],
            ["😪","sleepy"],["😴","sleeping"],["😷","mask sick"],["🤒","thermometer sick"],["🤕","bandage hurt"],["🤢","nauseated"],["🤧","sneeze"],["🥵","hot"],
            ["🥶","cold"],["😵","dizzy"],["🤯","mind blown"],["🥳","party"],["😎","cool sunglasses"],["🤓","nerd"],["🧐","monocle"],["😕","confused"],
            ["😟","worried"],["🙁","frown"],["😮","open mouth surprised"],["😯","hushed"],["😲","astonished"],["😳","flushed"],["🥺","pleading"],["😦","frown"],
            ["😧","anguished"],["😨","fearful"],["😰","anxious sweat"],["😥","sad relieved"],["😢","cry sad"],["😭","sob cry"],["😱","scream"],["😖","confounded"],
            ["😣","persevere"],["😞","disappointed"],["😓","sweat"],["😩","weary"],["😫","tired"],["🥱","yawn"],["😤","triumph"],["😡","angry pout"],
            ["😠","angry"],["🤬","cursing"],["😈","devil"],["💀","skull"],["💩","poo"],["🤡","clown"],["👻","ghost"],["👽","alien"]] },
        { name: "People", icon: "👍", items: [
            ["👍","thumbs up like yes"],["👎","thumbs down no"],["👌","ok"],["🤌","pinched"],["✌️","victory peace"],["🤞","fingers crossed"],["🤟","love you"],["🤘","rock"],
            ["🤙","call me"],["👈","left"],["👉","right"],["👆","up"],["👇","down"],["☝️","point up"],["✋","hand raised"],["🤚","back hand"],
            ["🖐️","hand"],["🖖","vulcan"],["👋","wave hello bye"],["👏","clap"],["🙌","raised hands celebrate"],["👐","open hands"],["🤲","palms"],["🤝","handshake"],
            ["🙏","pray thanks please"],["✍️","writing"],["💪","muscle strong"],["🧠","brain"],["👀","eyes look"],["👁️","eye"],["👄","mouth"],["🧑‍💻","technologist computer"],
            ["🙋","raising hand"],["🤷","shrug"],["🤦","facepalm"],["🙇","bow"],["💁","info"],["🙅","no gesture"],["🙆","ok gesture"],["🧑‍🤝‍🧑","people holding hands"]] },
        { name: "Animals", icon: "🐶", items: [
            ["🐶","dog"],["🐱","cat"],["🐭","mouse"],["🐹","hamster"],["🐰","rabbit"],["🦊","fox"],["🐻","bear"],["🐼","panda"],
            ["🐨","koala"],["🐯","tiger"],["🦁","lion"],["🐮","cow"],["🐷","pig"],["🐸","frog"],["🐵","monkey"],["🐔","chicken"],
            ["🐧","penguin"],["🐦","bird"],["🦄","unicorn"],["🐝","bee"],["🦋","butterfly"],["🐢","turtle"],["🐙","octopus"],["🐬","dolphin"],
            ["🌸","blossom flower"],["🌹","rose"],["🌻","sunflower"],["🌲","tree"],["🌵","cactus"],["🍀","clover luck"],["🌈","rainbow"],["☀️","sun"],
            ["🌙","moon"],["⭐","star"],["⚡","lightning"],["🔥","fire hot lit"],["❄️","snow"],["🌊","wave ocean"],["☔","rain umbrella"],["🌍","earth world"]] },
        { name: "Food", icon: "🍕", items: [
            ["🍎","apple"],["🍌","banana"],["🍇","grapes"],["🍓","strawberry"],["🍉","watermelon"],["🍑","peach"],["🍍","pineapple"],["🥑","avocado"],
            ["🍕","pizza"],["🍔","burger"],["🍟","fries"],["🌭","hot dog"],["🌮","taco"],["🌯","burrito"],["🍣","sushi"],["🍜","noodles ramen"],
            ["🍩","donut"],["🍪","cookie"],["🎂","cake birthday"],["🍰","cake"],["🍫","chocolate"],["🍿","popcorn"],["☕","coffee"],["🍵","tea"],
            ["🍺","beer"],["🍻","cheers beers"],["🍷","wine"],["🥂","cheers toast"],["🍹","cocktail"],["🥤","drink"],["🧃","juice"],["🍦","ice cream"]] },
        { name: "Travel", icon: "✈️", items: [
            ["🚗","car"],["🚕","taxi"],["🚌","bus"],["🚲","bike"],["🚀","rocket launch"],["✈️","plane travel"],["🚢","ship"],["🚆","train"],
            ["🏠","home house"],["🏢","office building"],["🏖️","beach"],["🏔️","mountain"],["🗽","statue"],["🗼","tower"],["🎡","ferris wheel"],["⛺","camping tent"],
            ["🗺️","map"],["🧭","compass"],["⏰","alarm clock"],["⌛","hourglass"],["📍","pin location"],["🚦","traffic light"],["🛑","stop"],["🚧","construction"]] },
        { name: "Activities", icon: "⚽", items: [
            ["⚽","soccer football"],["🏀","basketball"],["🏈","football"],["⚾","baseball"],["🎾","tennis"],["🏐","volleyball"],["🎳","bowling"],["⛳","golf"],
            ["🎮","game controller"],["🎲","dice"],["♟️","chess"],["🎯","target bullseye"],["🎨","art palette"],["🎬","movie"],["🎤","microphone sing"],["🎧","headphones"],
            ["🎸","guitar"],["🎹","piano"],["🎉","party tada celebrate"],["🎊","confetti"],["🎈","balloon"],["🎁","gift present"],["🏆","trophy win"],["🥇","gold medal first"]] },
        { name: "Objects", icon: "💡", items: [
            ["💡","idea bulb"],["💻","laptop computer"],["🖥️","desktop computer"],["⌨️","keyboard"],["🖱️","mouse"],["📱","phone mobile"],["☎️","telephone"],["📞","call phone"],
            ["📷","camera"],["🎥","video camera"],["📺","tv"],["🔋","battery"],["🔌","plug"],["💾","save disk"],["📁","folder"],["📄","document page"],
            ["📅","calendar"],["📌","pushpin"],["📎","paperclip"],["✂️","scissors"],["🔒","lock"],["🔑","key"],["🔨","hammer"],["🛠️","tools"],
            ["📦","package box"],["✉️","envelope mail"],["📧","email"],["📝","memo note"],["📊","chart bar"],["📈","chart up"],["📉","chart down"],["💰","money bag"]] },
        { name: "Symbols", icon: "❤️", items: [
            ["❤️","heart love red"],["🧡","orange heart"],["💛","yellow heart"],["💚","green heart"],["💙","blue heart"],["💜","purple heart"],["🖤","black heart"],["🤍","white heart"],
            ["💔","broken heart"],["💯","hundred"],["✅","check done yes"],["☑️","check box"],["✔️","check"],["❌","cross no"],["❎","cross"],["➕","plus"],
            ["➖","minus"],["❓","question"],["❗","exclamation"],["‼️","double exclamation"],["⚠️","warning"],["🚫","prohibited"],["🔴","red circle"],["🟢","green circle"],
            ["🔵","blue circle"],["⬆️","up arrow"],["⬇️","down arrow"],["➡️","right arrow"],["⬅️","left arrow"],["🔁","repeat"],["🆗","ok"],["🆕","new"]] },
    ]
    readonly property var allItems: categories.reduce((a, c) => a.concat(c.items), [])
    readonly property var shown: query
        ? allItems.filter(it => it[1].indexOf(query) >= 0)
        : null
    function choose(e) {
        recent = [e].concat(recent.filter(r => r !== e)).slice(0, 16)
        picked(e)
    }

    contentItem: Item {
        Rectangle {
            id: searchBox
            x: 12; y: 12; width: parent.width - 24; height: 32; radius: theme.radius
            color: theme.input
            border.color: search.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: search
                x: 32; width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                onTextChanged: root.query = text.trim().toLowerCase()
                Text { visible: !search.text; text: "Search emoji"; color: theme.textTertiary; font: search.font }
                Accessible.name: "Search emoji"
            }
        }
        // Category bar: jump to a section.
        Row {
            id: cats
            visible: !root.query
            x: 12; y: 52
            spacing: 2
            Repeater {
                model: root.categories
                Rectangle {
                    required property var modelData
                    required property int index
                    width: 36; height: 32; radius: theme.radius
                    color: ch.hovered ? theme.rowHover : "transparent"
                    Text { anchors.centerIn: parent; text: parent.modelData.icon; font.family: "Noto Color Emoji"; font.pixelSize: 18 }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: grid.positionViewAtIndex(parent.index + (root.recent.length ? 1 : 0), ListView.Beginning) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                }
            }
        }
        ListView {
            id: grid
            x: 12; y: root.query ? 52 : 92
            width: parent.width - 24; height: parent.height - y - 8
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: root.query ? [{ name: "Results", items: root.shown }]
                : (root.recent.length ? [{ name: "Recent", items: root.recent.map(e => [e, ""]) }] : []).concat(root.categories)
            delegate: Column {
                required property var modelData
                width: grid.width
                spacing: 4
                Text { text: parent.modelData.name; font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold; color: theme.textSecondary }
                Flow {
                    width: parent.width
                    Repeater {
                        model: parent.parent.modelData.items
                        Rectangle {
                            required property var modelData
                            width: 41; height: 36; radius: theme.radius
                            color: eh.hovered ? theme.rowHover : "transparent"
                            Text { anchors.centerIn: parent; text: parent.modelData[0]; font.family: "Noto Color Emoji"; font.pixelSize: 22 }
                            HoverHandler { id: eh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.choose(parent.modelData[0]) }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData[1] || modelData[0]
                        }
                    }
                }
            }
        }
    }
    onOpened: { search.text = ""; search.forceActiveFocus() }
}
