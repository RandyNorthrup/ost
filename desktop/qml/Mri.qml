pragma Singleton
import QtQuick

// People's MRIs in the UI, as the engine's identity module builds them
// (src/identity.rs). The only place QML turns a bare object id into an
// MRI; your own MRI and object id come from the signed-in identity
// (backend.userMri, backend.userOid), and anyone else's MRI is kept with
// whatever prefix it has (8:orgid:, 8:live:, 28:…).
QtObject {
    readonly property string workPrefix: "8:orgid:"

    /// A work user's MRI from their Entra object id (directory results:
    /// Graph, people pickers, sharing).
    function work(objectId) { return workPrefix + objectId }

    /// A resource account's (call queue, auto attendant) MRI from its
    /// object id.
    function appEndpoint(objectId) { return "28:orgid:" + objectId }
}
