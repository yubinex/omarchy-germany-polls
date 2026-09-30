.pragma library

// Shared DAWUM parsing for the bar widget and panel.
//
// A parliament's figure is the average of each institute's newest poll
// taken within `windowDays` of the most recent poll for that parliament, so
// a single outlier institute cannot flip the map on its own. State polls are
// rare; most states resolve to exactly one poll.

var windowDays = 30
// State polls older than this are drawn muted on the map.
var staleDays = 180

var partyColors = {
  "CDU/CSU": "#5d636e", "CDU": "#5d636e", "CSU": "#5d636e",
  "AfD": "#009ee0",
  "SPD": "#e3000f",
  "Grüne": "#46962b",
  "Linke": "#be3075",
  "FDP": "#ffcc00",
  "BSW": "#7d2a5c",
  "Freie Wähler": "#f39200",
  "BVB/FW": "#f39200",
  "SSW": "#003c8f",
  "Volt": "#562883",
  "BIW": "#8a6d3b",
  "Bayernpartei": "#6fb7e6",
  "NPD": "#8b4726"
}

var otherColor = "#8a8a8a"

function partyColor(shortcut) {
  return partyColors[shortcut] || otherColor
}

function dayNumber(iso) {
  var parts = String(iso).split("-")
  return Math.floor(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) / 86400000)
}

// DAWUM's website slugs spell umlauts out and drop the "(NRW)" suffix.
function dawumUrl(parliamentShortcut) {
  var slug = String(parliamentShortcut).replace(/\s*\(.*\)\s*$/, "")
    .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss")
    .replace(/\s+/g, "-")
  return "https://dawum.de/" + slug + "/"
}

// Returns { updated, parliaments: { <id>: summary } } or null when the
// payload is not a DAWUM database.
function parse(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || !data.Surveys || !data.Parliaments || !data.Parties) return null

  var byParliament = {}
  for (var id in data.Surveys) {
    var survey = data.Surveys[id]
    if (!survey || !survey.Results || !survey.Date) continue
    var key = String(survey.Parliament_ID)
    if (!byParliament[key]) byParliament[key] = []
    byParliament[key].push(survey)
  }

  var parliaments = {}
  for (var pid in byParliament) {
    var info = data.Parliaments[pid]
    if (!info) continue
    var surveys = byParliament[pid].sort(function(a, b) { return b.Date.localeCompare(a.Date) })
    var newest = dayNumber(surveys[0].Date)

    var used = []
    var seenInstitutes = {}
    for (var i = 0; i < surveys.length; ++i) {
      var s = surveys[i]
      if (newest - dayNumber(s.Date) > windowDays) break
      if (seenInstitutes[s.Institute_ID]) continue
      seenInstitutes[s.Institute_ID] = true
      used.push(s)
    }

    var sums = {}
    var counts = {}
    for (var u = 0; u < used.length; ++u) {
      for (var party in used[u].Results) {
        var value = Number(used[u].Results[party])
        if (isNaN(value)) continue
        sums[party] = (sums[party] || 0) + value
        counts[party] = (counts[party] || 0) + 1
      }
    }

    var results = []
    for (var partyId in sums) {
      var partyInfo = data.Parties[partyId]
      var shortcut = partyInfo ? partyInfo.Shortcut : "?"
      results.push({
        party: shortcut,
        name: partyInfo ? partyInfo.Name : shortcut,
        percent: Math.round(sums[partyId] / counts[partyId] * 10) / 10,
        color: partyColor(shortcut),
        other: partyId === "0"
      })
    }
    // "Sonstige" is never a leader, however large; keep it last.
    results.sort(function(a, b) {
      if (a.other !== b.other) return a.other ? 1 : -1
      return b.percent - a.percent
    })

    var institutes = used.map(function(s) {
      var inst = data.Institutes ? data.Institutes[s.Institute_ID] : null
      return inst ? inst.Name : "?"
    })

    parliaments[pid] = {
      id: pid,
      shortcut: info.Shortcut,
      name: info.Name,
      election: info.Election,
      date: surveys[0].Date,
      pollCount: used.length,
      institutes: institutes,
      results: results,
      leader: results.length ? results[0] : null,
      margin: results.length > 1 && !results[1].other ? results[0].percent - results[1].percent : 0,
      url: dawumUrl(info.Shortcut)
    }
  }

  return {
    updated: data.Database && data.Database.Last_Update ? data.Database.Last_Update : "",
    parliaments: parliaments
  }
}

function ageDays(summary, nowMs) {
  if (!summary) return Infinity
  return Math.floor(nowMs / 86400000) - dayNumber(summary.date)
}

function sourceLine(summary) {
  if (!summary) return ""
  if (summary.pollCount === 1) return summary.institutes[0] + " · " + formatDate(summary.date)
  return "Ø " + summary.pollCount + " polls · latest " + formatDate(summary.date)
}

function formatDate(iso) {
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var parts = String(iso).split("-")
  return Number(parts[2]) + " " + months[Number(parts[1]) - 1] + " " + parts[0]
}

function formatPercent(value) {
  var rounded = Math.round(value * 10) / 10
  return (rounded % 1 === 0 ? rounded.toFixed(0) : rounded.toFixed(1)) + "%"
}
