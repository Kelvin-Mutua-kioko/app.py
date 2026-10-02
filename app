from flask import Flask, jsonify, request, send_from_directory, render_template
from werkzeug.utils import secure_filename
from pathlib import Path
import requests

BASE_DIR = Path(__file__).resolve().parent

MUSIC_DIR = BASE_DIR / "music"
LYRICS_DIR = BASE_DIR / "lyrics"

ALLOWED_AUDIO = {
    ".mp3",
    ".wav",
    ".ogg",
    ".m4a",
    ".aac",
    ".flac"
}

MUSIC_DIR.mkdir(exist_ok=True)
LYRICS_DIR.mkdir(exist_ok=True)

app = Flask(
    __name__,
    template_folder="templates",
    static_folder="static"
)

app.config["MAX_CONTENT_LENGTH"] = 250 * 1024 * 1024


# ============================================================
# HOME
# ============================================================

@app.route("/")
def home():
    return render_template("index.html")


# ============================================================
# ONLINE MUSIC SEARCH
# ============================================================

@app.route("/api/search")
def search_music():

    term = request.args.get("term", "").strip()

    if not term:
        return jsonify({
            "results": [],
            "count": 0
        })

    try:

        response = requests.get(
            "https://itunes.apple.com/search",
            params={
                "term": term,
                "media": "music",
                "entity": "song",
                "limit": 40
            },
            timeout=15
        )

        response.raise_for_status()

        data = response.json()

        results = []

        for song in data.get("results", []):

            results.append({

                "id": song.get("trackId"),

                "title":
                    song.get("trackName")
                    or "Unknown Song",

                "artist":
                    song.get("artistName")
                    or "Unknown Artist",

                "album":
                    song.get("collectionName")
                    or "",

                "artwork":
                    song.get("artworkUrl100")
                    or "",

                "previewUrl":
                    song.get("previewUrl")
                    or "",

                "storeUrl":
                    song.get("trackViewUrl")
                    or "",

                "source":
                    "Apple Music preview",

                "local":
                    False
            })

        return jsonify({
            "results": results,
            "count": len(results)
        })

    except requests.RequestException as error:

        return jsonify({
            "error": f"Music search failed: {error}"
        }), 502


# ============================================================
# LOCAL MUSIC LIBRARY
# ============================================================

@app.route("/api/local")
def local_music():

    results = []

    for file in sorted(MUSIC_DIR.iterdir()):

        if (
            file.is_file()
            and file.suffix.lower() in ALLOWED_AUDIO
        ):

            results.append({

                "id":
                    "local:" + file.name,

                "title":
                    file.stem,

                "artist":
                    "Local Library",

                "album":
                    "GentleBeats",

                "artwork":
                    "",

                "previewUrl":
                    "/api/stream/" + file.name,

                "source":
                    "Local file",

                "local":
                    True,

                "filename":
                    file.name
            })

    return jsonify({
        "results": results,
        "count": len(results)
    })


# ============================================================
# STREAM LOCAL AUDIO
# ============================================================

@app.route("/api/stream/<path:filename>")
def stream_audio(filename):

    safe_filename = secure_filename(filename)

    if not safe_filename:
        return jsonify({
            "error": "Invalid filename"
        }), 400

    file_path = MUSIC_DIR / safe_filename

    if not file_path.exists():
        return jsonify({
            "error": "File not found"
        }), 404

    if not file_path.is_file():
        return jsonify({
            "error": "Invalid file"
        }), 400

    return send_from_directory(
        MUSIC_DIR,
        safe_filename,
        conditional=True
    )


# ============================================================
# UPLOAD MUSIC
# ============================================================

@app.route("/api/upload", methods=["POST"])
def upload_music():

    uploaded_file = request.files.get("file")

    if not uploaded_file:
        return jsonify({
            "error": "No audio file supplied"
        }), 400

    if not uploaded_file.filename:
        return jsonify({
            "error": "No filename supplied"
        }), 400

    filename = secure_filename(
        uploaded_file.filename
    )

    extension = Path(filename).suffix.lower()

    if extension not in ALLOWED_AUDIO:

        return jsonify({
            "error":
                "Unsupported audio format. "
                "Use MP3, WAV, OGG, M4A, AAC or FLAC."
        }), 400

    destination = MUSIC_DIR / filename

    uploaded_file.save(destination)

    return jsonify({

        "ok": True,

        "message":
            f"{filename} added to your local library."

    })


# ============================================================
# LOCAL LYRICS
# ============================================================

@app.route("/api/lyrics/<path:filename>")
def get_lyrics(filename):

    safe_filename = secure_filename(filename)

    if not safe_filename:

        return jsonify({
            "lyrics": ""
        })

    song_name = Path(
        safe_filename
    ).stem

    txt_file = LYRICS_DIR / (
        song_name + ".txt"
    )

    lrc_file = LYRICS_DIR / (
        song_name + ".lrc"
    )

    if txt_file.exists():

        return jsonify({

            "lyrics":
                txt_file.read_text(
                    encoding="utf-8"
                ),

            "source":
                "Local licensed/user-supplied lyrics"
        })

    if lrc_file.exists():

        return jsonify({

            "lyrics":
                lrc_file.read_text(
                    encoding="utf-8"
                ),

            "source":
                "Local licensed/user-supplied lyrics"
        })

    return jsonify({

        "lyrics":
            "No local lyrics file was found for this song.",

        "source":
            ""
    })


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route("/health")
def health():

    return jsonify({
        "status": "ok",
        "app": "GentleBeats"
    })


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    app.run(
        host="127.0.0.1",
        port=5000,
        debug=True
    )
