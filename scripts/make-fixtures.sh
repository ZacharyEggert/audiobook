#!/usr/bin/env bash
# Regenerates Tests/Fixtures (PLAN §7). Output is committed; rerun after changing a recipe.
set -euo pipefail
cd "$(dirname "$0")/.."

out=Tests/Fixtures
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
rm -rf "$out"
mkdir -p "$out"

# bitexact drops encoder strings and timestamps, so reruns give identical bytes
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
bx=(-fflags +bitexact -flags:a +bitexact)
sine() { echo "sine=frequency=${2:-440}:sample_rate=16000:duration=$1"; }

ff -f lavfi -i "color=c=0x14295A:s=64x64" -frames:v 1 "$tmp/cover.jpg"

# Three chapters over 6 s, shared by the chaptered fixtures. nero-chapters.m4b repeats these in Python.
cat >"$tmp/chapters.txt" <<'EOF'
;FFMETADATA1
title=Chapters Fixture
album=Chapters Fixture
artist=Test Author
album_artist=Test Author
composer=Test Narrator
genre=Audiobook
date=2024

[CHAPTER]
TIMEBASE=1/1000
START=0
END=2000
title=Opening
[CHAPTER]
TIMEBASE=1/1000
START=2000
END=4500
title=Middle
[CHAPTER]
TIMEBASE=1/1000
START=4500
END=6000
title=Ending
EOF
# Inputs 1 and 2 after the audio input: chapter metadata and cover art
in=(-i "$tmp/chapters.txt" -i "$tmp/cover.jpg")
tagged=(-map_metadata 1 -map_chapters 1 -map 0:a -map 2:v -c:v copy -disposition:v attached_pic)

# m4b: QuickTime chapter track only (no chpl), with covr
ff -f lavfi -i "$(sine 6)" "${in[@]}" "${tagged[@]}" -c:a aac -b:a 16k -movflags +disable_chpl "${bx[@]}" "$out/chapters.m4b"

# m4b: Nero chpl only, plus a freeform ----:com.apple.iTunes:SERIES atom (what m4b-tool writes)
ff -f lavfi -i "$(sine 6)" -i "$tmp/chapters.txt" -map_metadata 1 -map_chapters -1 -c:a aac -b:a 16k "${bx[@]}" "$out/nero-chapters.m4b"
python3 - "$out/nero-chapters.m4b" <<'PY'
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())

def box(typ, payload):
    return struct.pack(">I4s", 8 + len(payload), typ) + payload

def find(start, end, typ):
    while start + 8 <= end:
        size, t = struct.unpack_from(">I4s", data, start)
        if t == typ:
            return start, size
        start += size
    sys.exit(f"{typ} not found in {path}")

def append(boxpath, child):
    """Append child to the last box in boxpath and grow every ancestor's size."""
    start, end, chain = 0, len(data), []
    for typ in boxpath:
        off, size = find(start, end, typ)
        chain.append(off)
        start, end = off + 8 + (4 if typ == b"meta" else 0), off + size
    data[end:end] = child
    for off in chain:
        struct.pack_into(">I", data, off, struct.unpack_from(">I", data, off)[0] + len(child))

# Inserting bytes is only safe when moov comes after mdat (no chunk offsets move)
off, size = find(0, len(data), b"moov")
assert off + size == len(data), "moov must be the last top-level box"

chapters = [(0.0, "Opening"), (2.0, "Middle"), (4.5, "Ending")]
chpl = b"\x01\x00\x00\x00" + b"\x00" * 4 + bytes([len(chapters)])  # version 1, reserved, count
for start, title in chapters:
    t = title.encode()
    chpl += struct.pack(">QB", round(start * 10_000_000), len(t)) + t  # 100 ns units
append([b"moov", b"udta"], box(b"chpl", chpl))

freeform = box(b"mean", b"\0\0\0\0com.apple.iTunes") + box(b"name", b"\0\0\0\0SERIES") + box(b"data", struct.pack(">II", 1, 0) + b"Fixture Saga")
append([b"moov", b"udta", b"meta", b"ilst"], box(b"----", freeform))
open(path, "wb").write(data)
PY

# mp3: ID3v2.4 CHAP/CTOC + APIC
ff -f lavfi -i "$(sine 6)" "${in[@]}" "${tagged[@]}" -c:a libmp3lame -b:a 32k "${bx[@]}" "$out/chapters.mp3"

# flac: Vorbis CHAPTERxxx comments + PICTURE block. The flac muxer drops chapters, so write the comments directly.
ff -f lavfi -i "$(sine 6)" "${in[@]}" "${tagged[@]}" -c:a flac -sample_fmt s16 -ar 8000 \
  -metadata CHAPTER001=00:00:00.000 -metadata CHAPTER001NAME=Opening \
  -metadata CHAPTER002=00:00:02.000 -metadata CHAPTER002NAME=Middle \
  -metadata CHAPTER003=00:00:04.500 -metadata CHAPTER003NAME=Ending \
  "${bx[@]}" "$out/chapters.flac"

# mp3 file with tags: mp3 <out> <seconds> <title> <album> <track> [extra ffmpeg args]
mp3() {
  local o="$1" d="$2" title="$3" album="$4" track="$5"
  shift 5
  ff -f lavfi -i "$(sine "$d" $((300 + track * 100)))" -c:a libmp3lame -b:a 32k \
    -metadata title="$title" -metadata album="$album" -metadata artist="Test Author" \
    -metadata track="$track" "$@" "${bx[@]}" "$o"
}

# Folder book: natural sort must put "Part 10" last
mkdir -p "$out/multi-mp3"
mp3 "$out/multi-mp3/Part 1.mp3" 2 "Part One" "Multi MP3 Fixture" 1
mp3 "$out/multi-mp3/Part 2.mp3" 2 "Part Two" "Multi MP3 Fixture" 2
mp3 "$out/multi-mp3/Part 10.mp3" 2 "Part Ten" "Multi MP3 Fixture" 3
cp "$tmp/cover.jpg" "$out/multi-mp3/cover.jpg"

# Multi-disc: CD1/CD2 subfolders merge into one book
for disc in 1 2; do
  mkdir -p "$out/multi-disc/CD$disc"
  for track in 1 2; do
    mp3 "$out/multi-disc/CD$disc/0$track.mp3" 2 "Disc $disc Track $track" "Multi Disc Fixture" "$track" -metadata disc="$disc/2"
  done
done

# CBR mp3 without a Xing header (duration fallback) + CUE sidecar. 00:04:37 = 4 s + 37/75 s.
mp3 "$out/book.mp3" 6 "Cue Fixture" "Cue Fixture" 1 -write_xing 0
cat >"$out/book.cue" <<'EOF'
PERFORMER "Test Author"
TITLE "Cue Fixture"
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Part One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Part Two"
    INDEX 01 00:02:00
  TRACK 03 AUDIO
    TITLE "Part Three"
    INDEX 01 00:04:37
EOF

# OverDrive: TXXX MediaMarkers, ID3v2.3 with a non-ASCII title so text frames are UTF-16
markers='<Markers><Marker><Name>Chapter 1</Name><Time>0:00.000</Time></Marker><Marker><Name>Chapter 2</Name><Time>0:02.500</Time></Marker><Marker><Name>Chapter 3</Name><Time>0:04.000</Time></Marker></Markers>'
mp3 "$out/overdrive.mp3" 6 "Überdrive Fixture" "Überdrive Fixture" 1 -id3v2_version 3 -metadata "OverDrive MediaMarkers=$markers"

# VBR mp3 with a Xing header: 5 s tone then 5 s noise, so frame sizes really vary
ff -f lavfi -i "$(sine 5)" -f lavfi -i "anoisesrc=duration=5:sample_rate=16000:amplitude=0.3:seed=1" \
  -filter_complex concat=n=2:v=0:a=1 -c:a libmp3lame -q:a 6 "${bx[@]}" "$out/vbr.mp3"

# Truncated mid-moov: box sizes run past end of file
size=$(wc -c <"$out/chapters.m4b")
head -c $((size - 64)) "$out/chapters.m4b" >"$out/corrupt.m4b"

# Zip of a folder book. Fixed mtimes + TZ keep the archive stable.
mkdir -p "$tmp/zip/Zip Fixture"
mp3 "$tmp/zip/Zip Fixture/01.mp3" 2 "Zip One" "Zip Fixture" 1
mp3 "$tmp/zip/Zip Fixture/02.mp3" 2 "Zip Two" "Zip Fixture" 2
find "$tmp/zip" -exec touch -t 202401010000 {} +
(cd "$tmp/zip" && TZ=UTC zip -qrX - "Zip Fixture") >"$out/book.zip"

# Sanity checks
chapters() { ffprobe -v error -show_chapters -of csv "$1" | wc -l | tr -d ' '; }
for f in chapters.m4b nero-chapters.m4b chapters.mp3 chapters.flac; do
  [[ "$(chapters "$out/$f")" == 3 ]] || { echo "error: $f does not have 3 chapters" >&2; exit 1; }
done
! grep -q chpl "$out/chapters.m4b" || { echo "error: chapters.m4b has a chpl atom" >&2; exit 1; }
total=$(find "$out" -type f -exec cat {} + | wc -c)
((total < 2000000)) || { echo "error: fixtures are $total bytes (limit 2 MB)" >&2; exit 1; }
echo "Fixtures: $(find "$out" -type f | wc -l | tr -d ' ') files, $total bytes"
