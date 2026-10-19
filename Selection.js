.pragma library

function key(item) {
  var row = item || {}
  // Playlist positions distinguish copies; history timestamps distinguish repeat listens.
  return String(row.uri || "") + "|" + String(row.playlistPosition !== undefined
    ? row.playlistPosition : (row.playedAt || row.addedAt || ""))
}

function select(visible, selected, index, anchor, toggle, range) {
  if (index < 0 || index >= visible.length) return selected
  var next = toggle ? Object.assign({}, selected) : ({})
  var first = range && anchor >= 0 ? Math.min(anchor, index) : index
  var last = range && anchor >= 0 ? Math.max(anchor, index) : index
  for (var i = first; i <= last; i++) {
    var item = visible[i]
    if (!item || item.kind !== "item") continue
    var identity = key(item)
    if (toggle && !range && next[identity]) delete next[identity]
    else next[identity] = true
  }
  return next
}

function items(source, selected) {
  return source.filter(function(item, index) { return selected[key(item, index)] === true })
}

function retain(source, selected) {
  var next = ({})
  source.forEach(function(item, index) {
    var identity = key(item, index)
    if (selected[identity]) next[identity] = true
  })
  return next
}
