#!/usr/bin/env python3
"""A stand-in for an AIOStreams server, for screenshots: the Jellyfin API calls the apps make,
answered from a made-up catalogue whose artwork art.py draws, so the pictures show no one's
films, servers or accounts.

    python3 tools/demo-server/server.py [--port 8096] [--video demo.mp4]

The API sits at http://127.0.0.1:8096/jellyfin, as an AIOStreams server's does.
"""

import argparse
import json
import re
import sys
import time
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).parent))
import art  # noqa: E402

SERVER_ID = "d3m0d3m0d3m0d3m0d3m0d3m0d3m0d3m0"
TOKEN = "demo-token"
TICKS = 10_000_000

# name, colour of their initial's circle
USERS = [("Alex", (194, 181, 228)), ("Jordan", (184, 222, 242)), ("Sam", (255, 216, 224)), ("Kids", (210, 242, 214))]

PALETTES = {
    "aurora": ((10, 14, 40), (40, 110, 120), (170, 255, 200), [(20, 40, 60), (12, 24, 40), (6, 12, 22)]),
    "dusk": ((40, 20, 70), (240, 120, 90), (255, 220, 150), [(70, 30, 60), (40, 18, 40), (20, 10, 24)]),
    "desert": ((90, 140, 200), (250, 200, 140), (255, 245, 210), [(210, 140, 80), (170, 100, 60), (120, 70, 40)]),
    "ocean": ((10, 40, 80), (60, 150, 190), (230, 245, 255), [(20, 70, 110), (12, 50, 85), (6, 30, 60)]),
    "ember": ((40, 8, 10), (220, 90, 40), (255, 200, 120), [(90, 20, 20), (55, 12, 14), (25, 6, 8)]),
    "pastel": ((120, 100, 180), (250, 190, 210), (255, 250, 230), [(170, 120, 170), (130, 90, 140), (90, 60, 100)]),
    "neon": ((8, 6, 30), (70, 20, 120), (255, 80, 200), [(30, 10, 60), (18, 6, 40), (8, 2, 20)]),
    "forest": ((20, 50, 40), (140, 190, 150), (250, 240, 200), [(30, 80, 50), (20, 55, 35), (10, 30, 20)]),
    "storm": ((30, 35, 45), (110, 120, 140), (220, 225, 235), [(50, 55, 65), (35, 38, 48), (18, 20, 28)]),
    "teal": ((5, 40, 45), (40, 160, 150), (220, 255, 245), [(15, 70, 70), (8, 48, 50), (4, 26, 30)]),
}

MOVIES = [
    ("Northern Lights", 2025, "aurora", True, ["Drama", "Adventure"], 8.1, "PG-13", 128,
     "A glaciologist and her estranged brother cross the Arctic in winter to finish their late father's last survey."),
    ("The Last Lighthouse", 2024, "dusk", False, ["Mystery", "Thriller"], 7.4, "PG-13", 112,
     "When the light on a remote island goes dark, the new keeper finds the logbook ends mid-sentence."),
    ("Desert Bloom", 2025, "desert", False, ["Drama"], 7.8, "PG", 104,
     "A botanist returns to the town she left to save the one garden that never stopped growing."),
    ("Tidewater", 2023, "ocean", False, ["Thriller"], 6.9, "R", 97,
     "A storm, a stranded ferry and twelve strangers who all have a reason to be on board."),
    ("Ember Valley", 2026, "ember", False, ["Action", "Adventure"], 7.2, "PG-13", 121,
     "Two rival firefighting crews have one night to hold the line above their hometown."),
    ("Paper Moons", 2024, "pastel", True, ["Comedy", "Romance"], 7.6, "PG", 99,
     "An origami artist and a planetarium guide keep meeting at the same late-night bus stop."),
    ("Static", 2025, "neon", True, ["Science Fiction"], 7.0, "R", 109,
     "A radio engineer starts receiving tomorrow's broadcasts and can't stop listening."),
    ("Evergreen", 2026, "forest", False, ["Family", "Adventure"], 7.9, "PG", 95,
     "Three siblings follow a hand-drawn map into the oldest forest in the county."),
]

SHOWS = [
    ("Signal & Noise", 2025, "teal", False, ["Science Fiction", "Drama"], 8.4, "TV-14", 2,
     ["Carrier", "Interference", "Handshake", "Dead Air", "Feedback", "Bandwidth"],
     "A small observatory picks up a pattern in the noise, and the town around it starts to change."),
    ("Harbour Lights", 2024, "storm", True, ["Crime", "Drama"], 7.7, "TV-MA", 1,
     ["Low Tide", "The Ferryman", "Moorings", "Undertow", "Squall", "Safe Harbour"],
     "A detective transferred to a fishing town finds every case leads back to the same pier."),
    ("The Quiet Year", 2026, "pastel", False, ["Drama", "Comedy"], 8.0, "TV-PG", 1,
     ["January", "Thaw", "Long Weekend", "Open House", "Heatwave", "First Frost"],
     "A year in the life of a family who move to a village where nothing ever happens. Almost."),
    ("Orbit", 2023, "neon", True, ["Science Fiction"], 7.5, "TV-14", 1,
     ["Launch", "Apogee", "Drift", "Blackout", "Reentry", "Splashdown"],
     "Six strangers wake on a station that should have been decommissioned years ago."),
]

CAST = ["Mara Ellison", "Theo Achebe", "Ines Calloway", "Ruben Vasquez", "June Okafor", "Felix Brandt"]
ROLES = ["Lead", "Supporting", "Supporting", "Guest", "Guest", "Guest"]


def make_id(*parts):
    return re.sub(r"[^a-z0-9]", "", "".join(parts).lower())[:32].ljust(32, "0")


ITEMS = {}
ART = {}  # id -> (palette, seed, night, title)


def _base(item_id, name, kind, year, palette, night, genres, rating, official, minutes, overview, seed):
    ART[item_id] = (palette, seed, night, name)
    return {
        "Id": item_id,
        "Name": name,
        "ServerId": SERVER_ID,
        "Type": kind,
        "ProductionYear": year,
        "PremiereDate": f"{year}-03-14T00:00:00.0000000Z",
        "Overview": overview,
        "Genres": genres,
        "CommunityRating": rating,
        "OfficialRating": official,
        "RunTimeTicks": minutes * 60 * TICKS,
        "ImageTags": {"Primary": "p1", "Logo": "l1", "Thumb": "t1"},
        "BackdropImageTags": ["b1"],
        "Taglines": [],
        "People": [
            {"Id": make_id("person", n), "Name": n, "Role": r, "Type": "Actor"} for n, r in zip(CAST, ROLES)
        ],
        "IsFolder": kind in ("Series", "Season"),
        "MediaType": "Video" if kind in ("Movie", "Episode") else None,
        "LocationType": "FileSystem",
        "UserData": {"PlaybackPositionTicks": 0, "PlayedPercentage": 0, "Played": False, "IsFavorite": False},
    }


for i, (name, year, palette, night, genres, rating, official, minutes, overview) in enumerate(MOVIES):
    item = _base(make_id("movie", name), name, "Movie", year, palette, night, genres, rating, official, minutes, overview, i + 1)
    item["ParentId"] = make_id("view", "movies")
    ITEMS[item["Id"]] = item

for i, (name, year, palette, night, genres, rating, official, seasons, titles, overview) in enumerate(SHOWS):
    show = _base(make_id("show", name), name, "Series", year, palette, night, genres, rating, official, 48, overview, 100 + i)
    show["ParentId"] = make_id("view", "shows")
    show["Status"] = "Continuing"
    show["UserData"]["UnplayedItemCount"] = seasons * len(titles)
    ITEMS[show["Id"]] = show
    for s in range(1, seasons + 1):
        season = dict(_base(make_id("season", name, str(s)), f"Season {s}", "Season", year, palette, night, genres, rating, official, 0, "", 200 + i * 10 + s))
        season.update({"SeriesId": show["Id"], "SeriesName": name, "IndexNumber": s, "ParentId": show["Id"]})
        ITEMS[season["Id"]] = season
        for e, title in enumerate(titles, start=1):
            episode = _base(make_id("ep", name, str(s), str(e)), title, "Episode", year, palette, night or e % 2 == 0, genres,
                            round(rating - 0.4 + (e % 4) * 0.2, 1), official, 44 + e % 5,
                            f"Episode {e} of season {s}. {overview}", 1000 + i * 100 + s * 10 + e)
            episode.update({
                "SeriesId": show["Id"], "SeriesName": name, "SeasonId": season["Id"], "SeasonName": season["Name"],
                "IndexNumber": e, "ParentIndexNumber": s, "ParentId": season["Id"],
                "ParentBackdropItemId": show["Id"], "ParentBackdropImageTags": ["b1"],
                "ParentLogoItemId": show["Id"], "ParentLogoImageTag": "l1",
                "SeriesPrimaryImageTag": "p1",
                "ImageTags": {"Primary": "p1"}, "BackdropImageTags": [],
            })
            # The first show's first season is watched to episode 3, which is half done.
            if i == 0 and s == 1 and e <= 2:
                episode["UserData"].update({"Played": True, "PlayedPercentage": 100})
            if i == 0 and s == 1 and e == 3:
                episode["UserData"].update({"PlaybackPositionTicks": 21 * 60 * TICKS, "PlayedPercentage": 46})
            ITEMS[episode["Id"]] = episode

# Some of the catalogue is under way, watched or a favourite.
_movie = lambda n: ITEMS[make_id("movie", n)]
_movie("Northern Lights")["UserData"].update({"PlaybackPositionTicks": 72 * 60 * TICKS, "PlayedPercentage": 56})
_movie("Paper Moons")["UserData"].update({"PlaybackPositionTicks": 31 * 60 * TICKS, "PlayedPercentage": 31})
_movie("Desert Bloom")["UserData"].update({"Played": True, "PlayedPercentage": 100, "IsFavorite": True})
_movie("Static")["UserData"]["IsFavorite"] = True
ITEMS[make_id("show", "Signal & Noise")]["UserData"]["IsFavorite"] = True

VIEWS = [
    {"Id": make_id("view", "movies"), "Name": "Movies", "Type": "CollectionFolder", "CollectionType": "movies",
     "ServerId": SERVER_ID, "IsFolder": True, "ImageTags": {}, "BackdropImageTags": []},
    {"Id": make_id("view", "shows"), "Name": "Shows", "Type": "CollectionFolder", "CollectionType": "tvshows",
     "ServerId": SERVER_ID, "IsFolder": True, "ImageTags": {}, "BackdropImageTags": []},
]
VIEW_TYPES = {VIEWS[0]["Id"]: "Movie", VIEWS[1]["Id"]: "Series"}

CONFIGURATION = {
    "AudioLanguagePreference": "eng",
    "SubtitleLanguagePreference": "eng",
    "SubtitleMode": "Always",
    "PlayDefaultAudioTrack": True,
    "EnableNextEpisodeAutoPlay": True,
}


def user_dto(index=0):
    name, _ = USERS[index]
    return {
        "Id": make_id("user", name), "Name": name, "ServerId": SERVER_ID, "HasPassword": False,
        "HasConfiguredPassword": False, "PrimaryImageTag": "a1",
        "Configuration": CONFIGURATION, "Policy": {"IsAdministrator": False},
    }


def episodes_of(series_id, season_id=None):
    out = [i for i in ITEMS.values() if i["Type"] == "Episode" and i["SeriesId"] == series_id
           and (season_id is None or i["SeasonId"] == season_id)]
    return sorted(out, key=lambda e: (e["ParentIndexNumber"], e["IndexNumber"]))


def next_up(series_id=None):
    out = []
    for show in (i for i in ITEMS.values() if i["Type"] == "Series"):
        if series_id and show["Id"] != series_id:
            continue
        eps = episodes_of(show["Id"])
        if any(e["UserData"]["Played"] or e["UserData"]["PlaybackPositionTicks"] for e in eps):
            following = next((e for e in eps if not e["UserData"]["Played"] and not e["UserData"]["PlaybackPositionTicks"]), None)
            if following:
                out.append(following)
    return out


def resume():
    return [i for i in ITEMS.values() if i["UserData"]["PlaybackPositionTicks"] > 0]


def versions(item):
    """Versions as AIOStreams formats them, described plainly, from a demo provider."""
    stem = re.sub(r"[^a-z0-9]+", "-", item.get("SeriesName", item["Name"]).lower()).strip("-")
    if item["Type"] == "Episode":
        stem += f"-s{item['ParentIndexNumber']:02d}e{item['IndexNumber']:02d}"
    rows = [
        ("4K · Dolby Vision", "2160p 🎞 HEVC", "Dolby Vision · HDR10 🎧 Dolby Atmos 🔊 5.1", "18.4 GiB · 32.1 Mbps", "2160p-dolby-vision"),
        ("4K · HDR10", "2160p 🎞 HEVC", "HDR10 🎧 Dolby Digital Plus 🔊 5.1", "14.2 GiB · 24.8 Mbps", "2160p-hdr10"),
        ("1080p", "1080p 🎞 AVC", "SDR 🎧 Dolby Digital Plus 🔊 5.1", "6.1 GiB · 10.6 Mbps", "1080p"),
        ("720p", "720p 🎞 AVC", "SDR 🎧 AAC 🔊 Stereo", "2.3 GiB · 4.0 Mbps", "720p"),
    ]
    out = []
    for n, (name, line1, line2, size, release) in enumerate(rows):
        # The version's number first: ids are cut to 32 characters, which would drop it at the end.
        source_id = make_id("src", str(n), item["Id"])
        out.append({
            "Id": item["Id"] if n == 0 else source_id,
            "Name": name,
            "Path": None,
            "Protocol": "Http",
            "Container": "mp4",
            "Size": int(float(size.split()[0]) * 1024 ** 3),
            "SupportsDirectPlay": True,
            "MediaStreams": [
                {"Type": "Video", "Index": 0, "Codec": "h264"},
                {"Type": "Audio", "Index": 1, "Codec": "aac", "Language": "eng", "DisplayTitle": "English - AAC - Stereo"},
                {"Type": "Subtitle", "Index": 2, "Codec": "srt", "Language": "eng", "DisplayTitle": "English",
                 "IsExternal": True, "DeliveryUrl": f"/Videos/{item['Id']}/{source_id}/Subtitles/2/0/Stream.srt"},
            ],
            "aiostreams": {
                "id": source_id,
                "name": name,
                "description": f"🎥 {line1}\n📺 {line2}\n📦 {size}\n📁 {stem}-{release}.mkv\n🔍 Demo server",
            },
        })
    return out


SUBTITLES = """1
00:00:00,500 --> 00:01:00,000
This is how subtitles look in AIOStreams.

"""


def query_items(q):
    get = lambda k: (q.get(k) or q.get(k.lower()) or [None])[0]
    ids = get("Ids")
    if ids:
        return [ITEMS[i] for i in ids.split(",") if i in ITEMS]
    pool = list(ITEMS.values())
    types = get("IncludeItemTypes")
    parent = get("ParentId")
    if parent in VIEW_TYPES:
        types = types or VIEW_TYPES[parent]
        pool = [i for i in pool if i.get("ParentId") == parent]
    elif parent:
        pool = [i for i in pool if i.get("ParentId") == parent]
    if types:
        allowed = set(types.split(","))
        pool = [i for i in pool if i["Type"] in allowed]
    elif not parent:
        pool = [i for i in pool if i["Type"] in ("Movie", "Series")]
    term = get("SearchTerm")
    if term:
        pool = [i for i in pool if term.lower() in i["Name"].lower()]
    filters = get("Filters") or ""
    if "IsFavorite" in filters:
        pool = [i for i in pool if i["UserData"].get("IsFavorite")]
    start = int(get("StartIndex") or 0)
    limit = int(get("Limit") or 100)
    return pool[start:start + limit]


@lru_cache(maxsize=None)
def image(item_id, kind, max_w):
    if kind == "avatar":
        index = next((n for n, (name, _) in enumerate(USERS) if make_id("user", name) == item_id), 0)
        return art.jpeg(art.avatar(*USERS[index]))
    palette_name, seed, night, title = ART.get(item_id) or ("storm", 1, False, "Demo")
    palette = PALETTES[palette_name]
    if kind == "logo":
        img = art.logo(title)
        return art.png(img)
    if kind == "primary":
        item = ITEMS.get(item_id, {})
        if item.get("Type") == "Episode":
            return art.jpeg(art.backdrop(palette, seed, night, 1280, 720))
        return art.jpeg(art.poster(title, palette, seed, night))
    return art.jpeg(art.backdrop(palette, seed, night))


def person_image(person_id):
    return art.jpeg(art.avatar("·", (60, 60, 70)))


class Handler(BaseHTTPRequestHandler):
    # Keep-alive and ranges, as Apple's player expects of a video server.
    protocol_version = "HTTP/1.1"
    video: Path = None

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path[:160]))

    def _send(self, status, body=b"", kind="application/json", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, value, status=200):
        self._send(status, json.dumps(value).encode())

    def do_OPTIONS(self):
        self._send(204)

    def do_HEAD(self):
        self.do_GET()

    def _route(self):
        url = urlparse(self.path)
        path = re.sub(r"^/jellyfin", "", url.path, flags=re.I) or "/"
        return path, parse_qs(url.query)

    def _video(self):
        data_len = self.video.stat().st_size
        start, end = 0, data_len - 1
        match = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range") or "")
        status = 200
        if match:
            status = 206
            if match.group(1):
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else end
            else:
                start = data_len - int(match.group(2))
        end = min(end, data_len - 1)
        with open(self.video, "rb") as f:
            f.seek(start)
            body = f.read(end - start + 1)
        extra = {"Accept-Ranges": "bytes"}
        if status == 206:
            extra["Content-Range"] = f"bytes {start}-{end}/{data_len}"
        self._send(status, body, "video/mp4", extra)

    def do_GET(self):
        path, q = self._route()
        lower = path.lower()
        if lower == "/system/info/public":
            return self._json({"ServerName": "Demo Server", "Version": "10.10.0", "Id": SERVER_ID,
                               "ProductName": "Jellyfin Server", "StartupWizardCompleted": True,
                               "aiostreams": {"features": {}}})
        if lower == "/users/public":
            return self._json([{**user_dto(n), "Configuration": None} for n in range(len(USERS))])
        if lower in ("/users/me",) or re.fullmatch(r"/users/[0-9a-z]+", lower):
            return self._json(user_dto())
        if lower == "/quickconnect/enabled":
            return self._json(True)
        if lower == "/userviews" or re.fullmatch(r"/users/[0-9a-z]+/views", lower):
            return self._json({"Items": VIEWS, "TotalRecordCount": len(VIEWS)})
        if lower in ("/useritems/resume",) or re.fullmatch(r"/users/[0-9a-z]+/items/resume", lower):
            items = resume()
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        if lower == "/shows/nextup":
            items = next_up((q.get("SeriesId") or q.get("seriesId") or [None])[0])
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        m = re.fullmatch(r"/shows/([0-9a-z]+)/seasons", lower)
        if m:
            items = sorted((i for i in ITEMS.values() if i["Type"] == "Season" and i["SeriesId"] == m.group(1)),
                           key=lambda s: s["IndexNumber"])
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        m = re.fullmatch(r"/shows/([0-9a-z]+)/episodes", lower)
        if m:
            items = episodes_of(m.group(1), (q.get("SeasonId") or q.get("seasonId") or [None])[0])
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        m = re.fullmatch(r"/items/([0-9a-z]+)/similar", lower)
        if m:
            kind = ITEMS.get(m.group(1), {}).get("Type", "Movie")
            items = [i for i in ITEMS.values() if i["Type"] == kind and i["Id"] != m.group(1)][:8]
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        if lower == "/items" or re.fullmatch(r"/users/[0-9a-z]+/items", lower):
            items = query_items(q)
            return self._json({"Items": items, "TotalRecordCount": len(items)})
        m = re.fullmatch(r"/(?:users/[0-9a-z]+/)?items/([0-9a-z]+)", lower)
        if m and m.group(1) in ITEMS:
            return self._json(ITEMS[m.group(1)])
        m = re.fullmatch(r"/items/([0-9a-z]+)/images/(primary|backdrop|logo|thumb)(?:/\d+)?", lower)
        if m:
            item_id, kind = m.group(1), m.group(2)
            if item_id.startswith("person"):
                return self._send(200, person_image(item_id), "image/jpeg")
            if kind == "thumb":
                kind = "backdrop"
            body = image(item_id, kind, 0)
            return self._send(200, body, "image/png" if kind == "logo" else "image/jpeg")
        m = re.fullmatch(r"/users/([0-9a-z]+)/images/primary", lower)
        if m:
            return self._send(200, image(m.group(1), "avatar", 0), "image/jpeg")
        if lower.startswith("/displaypreferences/"):
            return self._json({"Id": "aiostreams-web", "CustomPrefs": {"saved": "1"}})
        if lower == "/aiostreams/history":
            played = [i for i in ITEMS.values() if i["UserData"]["Played"] or i["UserData"]["PlaybackPositionTicks"]]
            now = int(time.time() * 1000)
            entries = [{"userId": user_dto()["Id"], "itemKey": i["Id"], "kind": i["Type"].lower(),
                        "played": i["UserData"]["Played"], "playCount": 1, "positionMs": 0, "durationMs": 0,
                        "favorite": False, "lastPlayedAt": now - n * 86_400_000, "sortAt": now - n * 86_400_000,
                        "origin": "local", "tracker": None, "item": i} for n, i in enumerate(played)]
            return self._json({"items": entries, "cursor": None})
        if "/subtitles/" in lower:
            return self._send(200, SUBTITLES.encode(), "text/plain; charset=utf-8")
        if re.fullmatch(r"/videos/[0-9a-z]+/stream(\.\w+)?", lower) or lower == "/media/demo.mp4":
            return self._video()
        if lower in ("/aiostreams/users",):
            return self._json([])
        # Anything else answers as an empty list, which every page shows as nothing to show.
        return self._json({"Items": [], "TotalRecordCount": 0})

    def do_POST(self):
        path, q = self._route()
        lower = path.lower()
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        if lower == "/users/authenticatebyname" or lower == "/users/authenticatewithquickconnect":
            return self._json({"AccessToken": TOKEN, "ServerId": SERVER_ID, "User": user_dto(),
                               "SessionInfo": {"Id": "demo-session"}})
        if lower == "/quickconnect/initiate":
            return self._json({"Secret": "demo-secret", "Code": "428913", "Authenticated": False})
        m = re.fullmatch(r"/items/([0-9a-z]+)/playbackinfo", lower)
        if m and m.group(1) in ITEMS:
            return self._json({"MediaSources": versions(ITEMS[m.group(1)]), "PlaySessionId": "demo-play"})
        return self._send(204)

    def do_DELETE(self):
        return self._send(204)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8096)
    parser.add_argument("--video", type=Path, default=Path(__file__).parent / "demo.mp4")
    args = parser.parse_args()
    Handler.video = args.video
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"demo server on http://127.0.0.1:{args.port}/jellyfin", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
