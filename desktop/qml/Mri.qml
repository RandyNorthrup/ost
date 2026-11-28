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

    /// Someone on Teams free (a personal Microsoft account, 8:live:…, or
    /// another of Teams free's consumer kinds; identity::is_consumer_mri).
    /// An old Skype account keeps its Skype name (8:bart.ost1).
    function isConsumer(mri) {
        const m = String(mri || "")
        return /^8:(live|sip_profile|myspace|c2c|sms|facebook|fb):./.test(m) || /^8:[A-Za-z][A-Za-z0-9.,_-]{5,31}$/.test(m)
    }
}
