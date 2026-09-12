package.loaded["gettext"] = function(text)
    return text
end

package.loaded["ffi/util"] = {
    template = function(text, ...)
        local values = { ... }
        return (text:gsub("%%(%d+)", function(index)
            return tostring(values[tonumber(index)])
        end))
    end,
}

package.loaded["ui/widget/confirmbox"] = {}
package.loaded["device"] = {}
package.loaded["ui/event"] = { new = function() return {} end }
package.loaded["ui/widget/infomessage"] = { new = function(_, opts) return opts end }
package.loaded["optmath"] = { roundPercent = function(value) return value end }
package.loaded["ui/network/manager"] = {}

local shown_texts = {}
package.loaded["ui/uimanager"] = {
    show = function(_, message)
        table.insert(shown_texts, message.text)
    end,
    scheduleIn = function() end,
    unschedule = function() end,
    getElapsedTimeSinceBoot = function() return 0 end,
}
local warned = {}
package.loaded["logger"] = {
    dbg = function() end,
    warn = function(...)
        table.insert(warned, { ... })
    end,
}
package.loaded["ui/time"] = { s = function(value) return value end }

local partial_calls = 0
local unhashable = { ["/tmp/missing.epub"] = true }
package.loaded["util"] = {
    partialMD5 = function(file)
        partial_calls = partial_calls + 1
        if unhashable[file] then error("cannot open") end
        return "computed:" .. tostring(file)
    end,
}

package.path = "koreader-plugin/bookorbit.koplugin/?.lua;" .. package.path

local ProgressSync = require("bookorbit_progress_sync")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local plugin = {}
ProgressSync.install(plugin)

-- The sidecar's cached partial_md5_checksum is trusted by KOReader forever, so
-- the plugin verifies it against the file before using it as the document
-- identity. A mismatch is repaired in the sidecar and reported to the plugin
-- so the path and book mappings can follow the content.

local saved_digest
local function doc_settings(stored)
    return {
        readSetting = function() return stored end,
        saveSetting = function(_, _, value) saved_digest = value end,
    }
end

plugin.ui = {
    document = {
        file = "/tmp/book.epub",
        info = { has_pages = true },
    },
    doc_settings = doc_settings(nil),
}
assertEqual(plugin:getDocumentDigest(), "computed:/tmp/book.epub", "an uncached digest is computed")
assertEqual(saved_digest, "computed:/tmp/book.epub", "the computed digest is written to the sidecar")
assertEqual(partial_calls, 1, "partial md5 called once")

assertEqual(plugin:getDocumentDigest(), "computed:/tmp/book.epub", "the verified digest is reused")
assertEqual(partial_calls, 1, "an opened document is verified once, not on every call")

plugin.document_digest = nil
plugin.ui.doc_settings = doc_settings("computed:/tmp/book.epub")
assertEqual(plugin:getDocumentDigest(), "computed:/tmp/book.epub", "a matching cached digest is kept")
assertEqual(partial_calls, 2, "the cached digest is still verified against the file")

local corrected = {}
plugin.document_digest = nil
saved_digest = nil
plugin.onDocumentDigestCorrected = function(_, file, previous, digest)
    table.insert(corrected, { file = file, previous = previous, digest = digest })
end
plugin.ui.doc_settings = doc_settings("stale-digest")
assertEqual(plugin:getDocumentDigest(), "computed:/tmp/book.epub", "the real digest wins over the stale cache")
assertEqual(saved_digest, "computed:/tmp/book.epub", "the corrected digest replaces the stale sidecar value")
assertEqual(#corrected, 1, "the state repair hook runs once")
assertEqual(corrected[1].file, "/tmp/book.epub", "the repair hook receives the file")
assertEqual(corrected[1].previous, "stale-digest", "the repair hook receives the stale digest")
assertEqual(corrected[1].digest, "computed:/tmp/book.epub", "the repair hook receives the real digest")

-- A file that cannot be hashed keeps whatever KOReader had.
plugin.document_digest = nil
plugin.ui.document.file = "/tmp/missing.epub"
plugin.ui.doc_settings = doc_settings("cached-missing")
assertEqual(plugin:getDocumentDigest(), "cached-missing", "an unhashable file falls back to the cached digest")

plugin.ui = nil
assertEqual(plugin:getDocumentDigest(), nil, "missing UI returns nil")

plugin.isLoggedIn = function()
    return true
end
assertEqual(plugin:reconcileProgressBeforeBookSync("digest", function() end), false, "manual book sync rejects missing UI")
plugin:updateProgress(false, true)
plugin:getProgress(false, true)
assertEqual(shown_texts[1], "No reader book is open.", "manual book sync explains missing reader book")
assertEqual(shown_texts[2], "No reader book is open.", "interactive push explains missing reader book")
assertEqual(shown_texts[3], "No reader book is open.", "interactive pull explains missing reader book")

print("bookorbit_progress_digest_test.lua: ok")
