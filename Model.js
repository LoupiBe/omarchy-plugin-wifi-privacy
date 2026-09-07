.pragma library

// Sanitizes a string for safe rendering in QML PlainText sinks:
// - Strips ANSI escape codes
// - Strips HTML/XML angle brackets and tags
// - Strips ASCII/Unicode control characters
// - Truncates to maxLen to avoid unbounded layout expansion
function sanitizeString(str, maxLen) {
  if (typeof str !== "string") return ""
  var limit = typeof maxLen === "number" ? maxLen : 64

  // Strip ANSI escape codes
  var clean = str.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")

  // Strip HTML / XML tags
  clean = clean.replace(/<[^>]*>/g, "")

  // Strip non-printable control characters (except space)
  clean = clean.replace(/[\x00-\x1F\x7F-\x9F]/g, "")

  // Trim whitespace
  clean = clean.trim()

  // Bounded length truncation
  if (clean.length > limit) {
    clean = clean.slice(0, limit)
  }

  return clean
}

function defaultStatus() {
  return {
    active: false,
    iface: "--",
    ssid: "--",
    uuid: "",
    hw_mac: "--",
    current_mac: "--",
    is_mac_randomized: false,
    is_trusted: false,
    real_hostname: "unknown",
    dhcp_hostname: "unknown",
    ipv6_tempaddr: false,
    avahi_hidden: false
  }
}

// Parses JSON status with strict consumer-side bounds:
// - Verifies input length <= 8192 bytes
// - Verifies line count <= 128 lines
// - Sanitizes all dynamic string fields
// - Returns previousState or safe default on failure
function parseStatus(rawJson, previousState) {
  var fallback = (previousState && typeof previousState === "object") ? previousState : defaultStatus()

  if (typeof rawJson !== "string") return fallback

  // Guard 1: Input byte length limit (8192 bytes)
  if (rawJson.length > 8192) {
    console.warn("wifi-privacy: rejected status payload exceeding 8192 bytes")
    return fallback
  }

  // Guard 2: Line count limit (128 lines)
  var lineCount = rawJson.split("\n").length
  if (lineCount > 128) {
    console.warn("wifi-privacy: rejected status payload exceeding 128 lines")
    return fallback
  }

  try {
    var parsed = JSON.parse(rawJson)
    if (!parsed || typeof parsed !== "object") return fallback

    return {
      active: Boolean(parsed.active),
      iface: sanitizeString(parsed.iface, 32) || "--",
      ssid: sanitizeString(parsed.ssid, 64) || "--",
      uuid: sanitizeString(parsed.uuid, 64),
      hw_mac: sanitizeString(parsed.hw_mac, 32).toUpperCase() || "--",
      current_mac: sanitizeString(parsed.current_mac, 32).toUpperCase() || "--",
      is_mac_randomized: Boolean(parsed.is_mac_randomized),
      is_trusted: Boolean(parsed.is_trusted),
      real_hostname: sanitizeString(parsed.real_hostname, 64) || "unknown",
      dhcp_hostname: sanitizeString(parsed.dhcp_hostname, 64) || "unknown",
      ipv6_tempaddr: Boolean(parsed.ipv6_tempaddr),
      avahi_hidden: Boolean(parsed.avahi_hidden)
    }
  } catch (err) {
    console.warn("wifi-privacy: JSON parse failure:", err)
    return fallback
  }
}
