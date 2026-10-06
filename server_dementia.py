import os
import re
import json
import wave
import struct
import hashlib
import secrets
import tempfile
import subprocess
from functools import wraps
from datetime import datetime, timedelta
from threading import Thread

import psycopg2
import numpy as np
import webrtcvad
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from groq import Groq
from cryptography.fernet import Fernet
from scipy.spatial.distance import cosine as cosine_distance
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

# ── configuration ──────────────────────────────────────────────────────────────

GROQ_API_KEY      = os.environ.get("GROQ_API_KEY", "")
DB_HOST           = os.environ.get("DB_HOST", "localhost")
DB_NAME           = os.environ.get("DB_NAME", "stt_db")
DB_USER           = os.environ.get("DB_USER", "jeeven")
DB_PASSWORD       = os.environ.get("DB_PASSWORD", "")
AUDIO_FOLDER      = os.environ.get("AUDIO_FOLDER",      "/home/osugiw/mcu_server/uploads")
TRANSCRIPT_FOLDER = os.environ.get("TRANSCRIPT_FOLDER", "/home/osugiw/mcu_server/transcripts")
SUMMARY_FOLDER    = os.environ.get("SUMMARY_FOLDER",    "/home/osugiw/mcu_server/summaries")
ENROLL_FOLDER     = os.environ.get("ENROLL_FOLDER",     "/home/osugiw/mcu_server/enrollments")
KEY_FILE          = os.environ.get("KEY_FILE",          "/home/osugiw/mcu_server/.fernet_key")

for folder in [AUDIO_FOLDER, TRANSCRIPT_FOLDER, SUMMARY_FOLDER, ENROLL_FOLDER]:
    os.makedirs(folder, exist_ok=True)

# ── confidence fusion weights (dementia: temporal + cognitive weighted higher) ──

WEIGHTS = {
    "semantic":  0.50,
    "temporal":  0.25,
    "cognitive": 0.25,
}

THRESHOLD_HIGH   = 0.75
THRESHOLD_MEDIUM = 0.50
THRESHOLD_LOW    = 0.30

# ── voice diarization config ───────────────────────────────────────────────────

VOICE_MATCH_THRESHOLD = 0.82
DIARIZE_SUBWINDOW_MS  = 500

TV_SPECTRAL_FLATNESS_THRESHOLD = 0.15
TV_ZCR_THRESHOLD               = 0.12
TV_ENERGY_VARIANCE_THRESHOLD   = 0.05

STT_MODEL = "whisper-large-v3"
LLM_MODEL = "llama-3.3-70b-versatile"

# ── encryption ─────────────────────────────────────────────────────────────────

def _load_or_create_fernet() -> Fernet:
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "rb") as f:
            key = f.read()
        print("[Encryption] Key loaded.")
    else:
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as f:
            f.write(key)
        os.chmod(KEY_FILE, 0o600)
        print(f"[Encryption] New key → {KEY_FILE}  ⚠️  BACK THIS UP!")
    return Fernet(key)

FERNET = _load_or_create_fernet()

def encrypt_file(path: str) -> str:
    with open(path, "rb") as f:
        data = f.read()
    enc_path = path + ".enc"
    with open(enc_path, "wb") as f:
        f.write(FERNET.encrypt(data))
    os.remove(path)
    return enc_path

def decrypt_file(enc_path: str) -> bytes:
    with open(enc_path, "rb") as f:
        return FERNET.decrypt(f.read())

# ── Groq client ────────────────────────────────────────────────────────────────

client = Groq(api_key=GROQ_API_KEY)

# ── Flask app ──────────────────────────────────────────────────────────────────

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024

# ── Bearer token auth ──────────────────────────────────────────────────────────

def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "Unauthorized"}), 401
        token_hash = _hash_token(auth[7:])
        try:
            with get_db() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT id FROM api_tokens WHERE token_hash=%s LIMIT 1;",
                        (token_hash,),
                    )
                    if not cur.fetchone():
                        return jsonify({"error": "Invalid token"}), 401
                    cur.execute(
                        "UPDATE api_tokens SET last_used=NOW() WHERE token_hash=%s;",
                        (token_hash,),
                    )
        except Exception as exc:
            return jsonify({"error": f"Auth DB error: {exc}"}), 500
        return f(*args, **kwargs)
    return decorated

# ── database ───────────────────────────────────────────────────────────────────

def get_db():
    return psycopg2.connect(
        host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )

def db_insert_recording(audio_path: str, device_id: str) -> int:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO recordings (audio_file, status, device_id) VALUES (%s,'uploaded',%s) RETURNING id;",
                (audio_path, device_id),
            )
            return cur.fetchone()[0]

def db_insert_transcript(recording_id: int, path: str, device_id: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO transcripts (recording_id, text, device_id) VALUES (%s,%s,%s);",
                (recording_id, path, device_id),
            )

def db_insert_summary(recording_id: int, path: str, device_id: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO summaries (recording_id, summary, device_id) VALUES (%s,%s,%s);",
                (recording_id, path, device_id),
            )

def db_update_status(recording_id: int, status: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE recordings SET status=%s WHERE id=%s;",
                (status, recording_id),
            )

def db_save_intent(recording_id: int, intent: dict, device_id: str) -> int:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO intents (
                    recording_id, task, temporal_cue, raw_quote,
                    semantic_score, temporal_score, cognitive_score,
                    fused_confidence, decision, action,
                    cognitive_signals, status, scheduled_time, device_id
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id;
            """, (
                recording_id,
                intent.get("task", ""),
                intent.get("temporal_cue", ""),
                intent.get("raw_quote", ""),
                intent.get("semantic_score", 0.0),
                intent.get("temporal_score", 0.0),
                intent.get("cognitive_score", 0.0),
                intent.get("fused_confidence", 0.0),
                intent.get("decision", "log"),
                intent.get("action", "log_only"),
                json.dumps(intent.get("cognitive_signals", {})),
                "pending",
                intent.get("scheduled_time"),
                device_id,
            ))
            return cur.fetchone()[0]

def db_save_voice_profile(device_id: str, embedding: np.ndarray):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM voice_profiles WHERE device_id=%s;", (device_id,))
            cur.execute(
                "INSERT INTO voice_profiles (device_id, label, embedding) VALUES (%s,'patient',%s);",
                (device_id, json.dumps(embedding.tolist())),
            )

def db_get_voice_profile(device_id: str) -> np.ndarray | None:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT embedding FROM voice_profiles WHERE device_id=%s LIMIT 1;",
                (device_id,),
            )
            row = cur.fetchone()
    if row:
        emb = row[0]
        return np.array(json.loads(emb) if isinstance(emb, str) else emb)
    return None

def db_save_memory_chunk(recording_id: int, device_id: str, content: str, embedding: list):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO memory_chunks (recording_id, device_id, content, embedding) VALUES (%s,%s,%s,%s::vector);",
                (recording_id, device_id, content, json.dumps(embedding)),
            )

def db_search_memory(query_embedding: list, device_id: str, limit: int = 5) -> list:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT content, created_at, 1 - (embedding <=> %s::vector) AS similarity
                FROM memory_chunks
                WHERE device_id = %s
                ORDER BY embedding <=> %s::vector
                LIMIT %s;
            """, (json.dumps(query_embedding), device_id, json.dumps(query_embedding), limit))
            return cur.fetchall()

# ── audio helpers ──────────────────────────────────────────────────────────────

def convert_to_wav(input_path: str, target_sr: int = 16000) -> str:
    ext = os.path.splitext(input_path)[1].lower()
    if ext == ".wav":
        return input_path
    wav_path = os.path.splitext(input_path)[0] + ".wav"
    print(f"[Pipeline] Converting {ext} → WAV ...")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", input_path,
         "-ar", str(target_sr), "-ac", "1", "-sample_fmt", "s16", wav_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not os.path.exists(wav_path):
        print(f"[Pipeline] FFmpeg error: {result.stderr}")
        return input_path
    print(f"[Pipeline] Converted → {wav_path}")
    return wav_path

def load_wav_samples(wav_path: str) -> tuple:
    with wave.open(wav_path, "rb") as wf:
        sr  = wf.getframerate()
        nch = wf.getnchannels()
        sw  = wf.getsampwidth()
        raw = wf.readframes(wf.getnframes())
    if sw == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sw == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        samples = np.frombuffer(raw, dtype=np.uint8).astype(np.float32) / 128.0 - 1.0
    if nch > 1:
        samples = samples.reshape(-1, nch).mean(axis=1)
    return samples, sr

def has_speech(wav_path: str, aggressiveness: int = 2, min_ratio: float = 0.1) -> bool:
    try:
        vad = webrtcvad.Vad(aggressiveness)
        with wave.open(wav_path, "rb") as wf:
            sr  = wf.getframerate()
            nch = wf.getnchannels()
            sw  = wf.getsampwidth()
            if sr not in (8000, 16000, 32000, 48000) or nch != 1 or sw != 2:
                return True
            spf = int(sr * 30 / 1000)
            bpf = spf * sw
            sf = tf = 0
            while True:
                frame = wf.readframes(spf)
                if len(frame) < bpf:
                    break
                tf += 1
                if vad.is_speech(frame, sr):
                    sf += 1
        if tf == 0:
            return False
        ratio = sf / tf
        print(f"[VAD] Speech ratio: {ratio:.2f} ({sf}/{tf} frames)")
        return ratio >= min_ratio
    except Exception as e:
        print(f"[VAD] Error: {e} — assuming speech")
        return True

# ── TV detection ───────────────────────────────────────────────────────────────

def detect_tv_audio(samples: np.ndarray, sr: int) -> dict:
    if len(samples) < sr:
        return {"is_tv": False, "confidence": 0.0}
    frame_size = 512
    flatness_scores = []
    for i in range(0, len(samples) - frame_size, frame_size):
        frame    = samples[i:i+frame_size]
        spectrum = np.abs(np.fft.rfft(frame * np.hanning(frame_size))) + 1e-10
        flatness_scores.append(np.exp(np.mean(np.log(spectrum))) / np.mean(spectrum))
    avg_flatness = np.mean(flatness_scores)
    hop = sr // 10
    energies = [np.sqrt(np.mean(samples[i:i+hop]**2)) for i in range(0, len(samples) - hop, hop)]
    energy_variance  = np.var(energies) / (np.mean(energies) + 1e-10)
    zcr              = np.mean(np.abs(np.diff(np.sign(samples)))) / 2
    silence_ratio    = np.sum(np.abs(samples) < 0.01) / len(samples)
    tv_signals = sum([
        avg_flatness > TV_SPECTRAL_FLATNESS_THRESHOLD,
        energy_variance < TV_ENERGY_VARIANCE_THRESHOLD,
        zcr > TV_ZCR_THRESHOLD,
        silence_ratio < 0.15,
    ])
    print(f"[TVDetect] flatness={avg_flatness:.3f} energy_var={energy_variance:.3f} zcr={zcr:.3f} silence={silence_ratio:.3f}")
    is_tv = tv_signals >= 3
    if is_tv:
        print(f"[TVDetect] 📺 TV detected ({tv_signals}/4 signals)")
    return {"is_tv": is_tv, "confidence": round(tv_signals / 4.0, 2)}

# ── MFCC voice embedding ───────────────────────────────────────────────────────

def compute_mfcc_embedding(samples: np.ndarray, sr: int,
                           n_mfcc: int = 40, n_fft: int = 512,
                           hop_length: int = 160) -> np.ndarray:
    from scipy.fft import dct
    samples      = np.append(samples[0], samples[1:] - 0.97 * samples[:-1])
    frames       = [samples[i:i+n_fft] * np.hanning(n_fft)
                    for i in range(0, len(samples) - n_fft, hop_length)]
    if not frames:
        return np.zeros(n_mfcc * 3)
    frames       = np.array(frames)
    power        = (np.abs(np.fft.rfft(frames, n=n_fft)) ** 2) / n_fft
    n_mels       = 40
    mel_low      = 2595 * np.log10(1 + 0 / 700)
    mel_high     = 2595 * np.log10(1 + (sr // 2) / 700)
    mel_pts      = np.linspace(mel_low, mel_high, n_mels + 2)
    hz_pts       = 700 * (10 ** (mel_pts / 2595) - 1)
    bin_pts      = np.floor((n_fft + 1) * hz_pts / sr).astype(int)
    filterbank   = np.zeros((n_mels, n_fft // 2 + 1))
    for m in range(1, n_mels + 1):
        for k in range(bin_pts[m-1], bin_pts[m]):
            if bin_pts[m] != bin_pts[m-1]:
                filterbank[m-1, k] = (k - bin_pts[m-1]) / (bin_pts[m] - bin_pts[m-1])
        for k in range(bin_pts[m], bin_pts[m+1]):
            if bin_pts[m+1] != bin_pts[m]:
                filterbank[m-1, k] = (bin_pts[m+1] - k) / (bin_pts[m+1] - bin_pts[m])
    mel_e  = np.dot(power, filterbank.T)
    mel_e  = np.where(mel_e == 0, np.finfo(float).eps, mel_e)
    mfccs  = dct(np.log(mel_e), type=2, axis=1, norm='ortho')[:, :n_mfcc]
    delta  = np.diff(mfccs, axis=0)
    emb    = np.concatenate([np.mean(mfccs, axis=0), np.std(mfccs, axis=0),
                             np.mean(delta, axis=0) if len(delta) > 0 else np.zeros(n_mfcc)])
    norm   = np.linalg.norm(emb)
    return emb / norm if norm > 0 else emb

def get_voice_embedding(wav_path: str) -> np.ndarray | None:
    try:
        samples, sr = load_wav_samples(wav_path)
        if len(samples) < sr:
            print("[VoiceID] Audio too short for enrollment")
            return None
        return compute_mfcc_embedding(samples, sr)
    except Exception as e:
        print(f"[VoiceID] Embedding error: {e}")
        return None

# ── Voice diarization (sub-window, 500ms) ─────────────────────────────────────

def diarize_and_filter_patient(wav_path: str, device_id: str,
                                min_segment_ms: int = 800) -> tuple:
    """
    Isolate patient voice segments using sub-window MFCC classification.
    Returns (filtered_wav_path, stats_dict).
    Falls back to full audio if no profile enrolled.
    """
    try:
        samples, sr = load_wav_samples(wav_path)
    except Exception as e:
        print(f"[Diarize] Could not load audio: {e}")
        return wav_path, {"label": "unknown"}

    tv = detect_tv_audio(samples, sr)
    if tv["is_tv"]:
        return wav_path, {"label": "tv"}

    profile = db_get_voice_profile(device_id)
    if profile is None:
        print("[Diarize] No voice profile — using full audio")
        return wav_path, {"label": "unknown"}

    # VAD segmentation
    pcm16      = (samples * 32768).astype(np.int16)
    frame_ms   = 30
    frame_samp = int(sr * frame_ms / 1000)
    vad        = webrtcvad.Vad(2)
    raw_segs   = []
    in_speech  = False
    seg_start  = 0
    for i in range(0, len(pcm16) - frame_samp, frame_samp):
        frame = pcm16[i:i+frame_samp].tobytes()
        try:
            is_s = vad.is_speech(frame, sr)
        except Exception:
            continue
        if is_s and not in_speech:
            seg_start = i; in_speech = True
        elif not is_s and in_speech:
            raw_segs.append((seg_start, i)); in_speech = False
    if in_speech:
        raw_segs.append((seg_start, len(pcm16)))

    # Merge short gaps, drop tiny segments
    merge_gap = int(sr * 0.5)
    merged = []
    for s, e in raw_segs:
        if merged and s - merged[-1][1] < merge_gap:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    min_samp = int(sr * min_segment_ms / 1000)
    merged   = [(s, e) for s, e in merged if e - s >= min_samp]
    total    = len(merged)
    print(f"[Diarize] {total} speech segment(s)")

    # Sub-window classification
    sub_size      = int(sr * DIARIZE_SUBWINDOW_MS / 1000)
    patient_parts = []
    total_windows = owner_windows = 0

    for s, e in merged:
        seg  = samples[s:e]
        kept = []
        for i in range(0, len(seg) - sub_size + 1, sub_size):
            window = seg[i:i+sub_size]
            total_windows += 1
            try:
                emb = compute_mfcc_embedding(window, sr)
                sim = float(1.0 - cosine_distance(profile, emb))
                if sim >= VOICE_MATCH_THRESHOLD:
                    kept.append(window)
                    owner_windows += 1
            except Exception as exc:
                print(f"[Diarize]  ⚠️  sub-window error: {exc}")
        label = "✅" if kept else "❌"
        print(f"[Diarize]  {label} seg {(e-s)/sr:.1f}s — {len(kept)}/{max(1, len(seg)//sub_size)} windows kept")
        patient_parts.extend(kept)

    print(f"[Diarize] {owner_windows}/{total_windows} sub-windows kept")

    if not patient_parts:
        return wav_path, {"label": "other", "patient_segments": 0, "total_segments": total_windows}

    # Reconstruct patient-only WAV
    silence_pad = np.zeros(int(sr * 0.1), dtype=np.float32)
    interleaved = []
    for part in patient_parts:
        interleaved.append(part)
        interleaved.append(silence_pad)
    filtered     = np.concatenate(interleaved)
    pcm_filtered = (filtered * 32768).astype(np.int16)
    filtered_path = wav_path.replace(".wav", "_patient.wav")
    with wave.open(filtered_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm_filtered.tobytes())

    return filtered_path, {
        "label":            "patient",
        "patient_segments": owner_windows,
        "total_segments":   total_windows,
        "patient_duration": round(len(filtered) / sr, 1),
    }

# ── transcription ──────────────────────────────────────────────────────────────

def transcribe(wav_path: str) -> str:
    print(f"[STT] Sending to Groq Whisper ({STT_MODEL})...")
    with open(wav_path, "rb") as f:
        result = client.audio.transcriptions.create(
            file=(os.path.basename(wav_path), f, "audio/wav"),
            model=STT_MODEL,
            response_format="text",
        )
    text = result.strip() if isinstance(result, str) else result.text.strip()
    print(f"[STT] Transcribed: {text[:80]}...")
    return text

# ── RAG memory ─────────────────────────────────────────────────────────────────

def get_text_embedding(text: str) -> list | None:
    try:
        words     = re.findall(r"\b\w+\b", text.lower())
        embedding = np.zeros(384)
        for word in words:
            h = int(hashlib.md5(word.encode()).hexdigest(), 16) % 384
            embedding[h] += 1.0
        for i in range(len(words) - 1):
            h = int(hashlib.md5((words[i] + "_" + words[i+1]).encode()).hexdigest(), 16) % 384
            embedding[h] += 0.5
        norm = np.linalg.norm(embedding)
        return (embedding / norm).tolist() if norm > 0 else embedding.tolist()
    except Exception as e:
        print(f"[RAG] Embedding error: {e}")
        return None

def chunk_text(text: str, chunk_size: int = 150, overlap: int = 30) -> list:
    words  = text.split()
    chunks = []
    i      = 0
    while i < len(words):
        chunk = " ".join(words[i:i+chunk_size])
        if chunk.strip():
            chunks.append(chunk)
        i += chunk_size - overlap
    return chunks

def index_transcript(transcript: str, recording_id: int, device_id: str):
    chunks  = chunk_text(transcript)
    indexed = 0
    print(f"[RAG] Indexing {len(chunks)} chunk(s)...")
    for chunk in chunks:
        emb = get_text_embedding(chunk)
        if emb:
            db_save_memory_chunk(recording_id, device_id, chunk, emb)
            indexed += 1
    print(f"[RAG] Indexed {indexed}/{len(chunks)} for device={device_id}")

def retrieve_context(question: str, device_id: str, limit: int = 5) -> list:
    emb = get_text_embedding(question)
    if not emb:
        return []
    return db_search_memory(emb, device_id, limit)

# ── keyword detection (dementia-specific) ─────────────────────────────────────

DANGER_KEYWORDS = [
    "help", "pain", "fall", "fell", "hurt", "emergency",
    "scared", "alone", "bleeding", "chest", "dizzy", "faint", "breathe",
]

FORGETTING_KEYWORDS = [
    "where am i", "who are you", "what day", "what year",
    "i forgot", "i don't remember", "i can't remember",
    "what is my name", "i don't know where",
]

def keyword_check(text: str) -> dict:
    text_lower = text.lower()
    return {
        "danger":     [kw for kw in DANGER_KEYWORDS     if kw in text_lower],
        "forgetting": [kw for kw in FORGETTING_KEYWORDS if kw in text_lower],
    }

# ── cognitive signals ──────────────────────────────────────────────────────────

FILLER_WORDS   = ["uh","um","er","ah","like","you know","i mean","so","well","basically","actually"]
TEMPORAL_WORDS = ["later","tomorrow","tonight","today","afternoon","morning","evening","next week","soon","at","by"]

def cognitive_signals(text: str) -> dict:
    words   = text.lower().split()
    total   = len(words) if words else 1
    fillers = sum(1 for w in words if w in FILLER_WORDS)
    density = round(fillers / total, 3)
    phrases = [" ".join(words[i:i+3]) for i in range(len(words)-2)]
    repeated = len(phrases) - len(set(phrases))
    hesitation = min(1.0, round(density * 3 + repeated / total, 3))
    return {
        "filler_count": fillers, "filler_density": density,
        "repeated_phrases": repeated, "hesitation_score": hesitation,
    }

def temporal_score(text: str) -> float:
    found    = [t for t in TEMPORAL_WORDS if t in text.lower()]
    if not found: return 0.0
    specific = [t for t in found if t in ["at","by","tomorrow","tonight","next week"]]
    return min(1.0, round(0.4 + len(specific) * 0.2 + len(found) * 0.1, 2))

# ── scheduled time parser ──────────────────────────────────────────────────────

def parse_scheduled_time(cue: str):
    if not cue:
        return None
    now = datetime.now()
    c   = cue.lower().strip()
    if "tonight" in c or "this evening" in c:
        return now.replace(hour=19, minute=0, second=0, microsecond=0)
    if "tomorrow morning" in c:
        return (now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
    if "tomorrow" in c:
        return (now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
    if "afternoon" in c:
        return now.replace(hour=14, minute=0, second=0, microsecond=0)
    if "morning" in c:
        return now.replace(hour=9, minute=0, second=0, microsecond=0)
    if "next week" in c:
        return now + timedelta(weeks=1)
    if "later" in c or "soon" in c:
        return now + timedelta(hours=2)
    m = re.search(r"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", c)
    if m:
        hour   = int(m.group(1))
        minute = int(m.group(2)) if m.group(2) else 0
        ampm   = m.group(3)
        if ampm == "pm" and hour != 12: hour += 12
        elif ampm == "am" and hour == 12: hour = 0
        t = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        return t if t >= now else t + timedelta(days=1)
    return None

# ── confidence fusion ──────────────────────────────────────────────────────────

def fuse_confidence(semantic: float, temporal: float, cognitive: dict) -> float:
    cog_scr = round(max(0.3, 1.0 - cognitive.get("hesitation_score", 0.0) * 0.7), 3)
    return round(min(1.0,
        WEIGHTS["semantic"]  * semantic  +
        WEIGHTS["temporal"]  * temporal  +
        WEIGHTS["cognitive"] * cog_scr
    ), 3)

def decide(fused: float) -> dict:
    if fused >= THRESHOLD_HIGH:
        return {"decision": "act",     "action": "notify_caregiver"}
    if fused >= THRESHOLD_MEDIUM:
        return {"decision": "confirm", "action": "ask_caregiver"}
    if fused >= THRESHOLD_LOW:
        return {"decision": "log",     "action": "log_only"}
    return     {"decision": "ignore",  "action": "none"}

# ── intent extraction ──────────────────────────────────────────────────────────

def extract_intents(transcript: str, recording_id: int, device_id: str) -> list:
    cog    = cognitive_signals(transcript)
    prompt = f"""You are an intent extraction system for a dementia patient monitoring device.

Analyse this transcript and extract any tasks, reminders or intentions the PATIENT expresses.

Look for:
- Semantic intent: "I need to...", "I should...", "remind me to...", "don't forget to...", "I have to..."
- Temporal cues: "later", "tomorrow", "tonight", "at [time]", "this afternoon"
- Hesitant or incomplete sentences still count as valid intent

Cognitive signals detected:
- Filler density: {cog['filler_density']} (0=fluent, 1=very hesitant)
- Hesitation score: {cog['hesitation_score']}

IMPORTANT:
- Only extract genuine PATIENT intentions, not caregiver instructions
- A hesitant "uh... I think I need to... um... pick up medicine" IS valid
- semantic_score: 0.0-1.0 — how clearly is this a genuine intent?
- If no intents found return empty list

Respond ONLY in valid JSON:
{{"intents": [{{"task": "plain text task", "temporal_cue": "when or empty string", "semantic_score": 0.0, "raw_quote": "exact phrase"}}]}}

Transcript:
{transcript}"""

    try:
        comp        = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
        )
        raw_intents = json.loads(comp.choices[0].message.content).get("intents", [])
        processed   = []

        for intent in raw_intents:
            semantic  = float(intent.get("semantic_score", 0.0))
            temp_cue  = intent.get("temporal_cue", "")
            temp_scr  = temporal_score(temp_cue + " " + intent.get("task", ""))
            fused     = fuse_confidence(semantic, temp_scr, cog)
            d         = decide(fused)
            sched     = parse_scheduled_time(temp_cue)

            full = {
                "task": intent.get("task", ""), "temporal_cue": temp_cue,
                "raw_quote": intent.get("raw_quote", ""),
                "semantic_score": round(semantic, 3),
                "temporal_score": round(temp_scr, 3),
                "cognitive_score": round(max(0.3, 1.0 - cog["hesitation_score"] * 0.7), 3),
                "fused_confidence": fused,
                "decision": d["decision"], "action": d["action"],
                "cognitive_signals": cog,
                "scheduled_time": sched.isoformat() if sched else None,
            }
            full["id"] = db_save_intent(recording_id, full, device_id)
            processed.append(full)
            level = "✅ HIGH" if fused >= THRESHOLD_HIGH else ("⚠️  MEDIUM" if fused >= THRESHOLD_MEDIUM else "🔹 LOW")
            print(f"[Intent] {level} '{full['task']}' fused={fused:.2f}")

        if not processed:
            print("[Intent] No intents detected.")
        return processed

    except Exception as e:
        print(f"[Intent Error] {e}")
        return []

# ── LLM danger/forgetting analysis (dementia-specific) ────────────────────────

def llm_analyse(transcript: str, kw: dict = None) -> dict:
    if kw is None:
        kw = {"danger": [], "forgetting": []}

    prompt = f"""You are a medical assistant monitoring a dementia patient wearing a recording device.

IMPORTANT:
- The transcript may contain MULTIPLE speakers — the patient and caregivers
- Only flag danger or forgetting if the PATIENT themselves expresses it
- Caregivers asking "are you okay?" are NOT patient distress

Respond ONLY in valid JSON:
{{
  "speakers_identified": "brief description",
  "patient_identified_as": "how you identified the patient",
  "summary": "detailed paragraph of conversation, mood, coherence and concerns",
  "danger_detected": true if the PATIENT is in genuine distress or danger,
  "danger_details": "describe in detail, or empty string",
  "forgetting_detected": true if the PATIENT shows clear confusion or memory loss,
  "forgetting_details": "describe signs in detail, or empty string",
  "alert_needed": true if a caregiver genuinely needs notification right now
}}

Keywords detected (hints only): {kw}

Transcript:
{transcript}"""

    try:
        comp = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
        )
        return json.loads(comp.choices[0].message.content)
    except Exception as e:
        print(f"[Analysis Error] {e}")
        return {
            "speakers_identified": "Unknown", "patient_identified_as": "Unknown",
            "summary": "Analysis unavailable.", "danger_detected": False,
            "danger_details": "", "forgetting_detected": False,
            "forgetting_details": "", "alert_needed": False,
        }

# ── caregiver RAG query ────────────────────────────────────────────────────────

def answer_caregiver_query(question: str, device_id: str, history: list = None) -> str:
    chunks = retrieve_context(question, device_id)
    context_text = "\n\n".join([f"[{str(r[1])[:16]}] {r[0]}" for r in chunks]) \
                   if chunks else "No relevant past context found."

    system_prompt = f"""You are a medical assistant helping a caregiver monitor their dementia patient.
You have access to the patient's past recordings as memory.
Always refer to the patient as "the patient" and answer the caregiver's questions directly.
If the answer is in the memory context, use it. If not, say so briefly.

--- PATIENT MEMORY (relevant past recordings) ---
{context_text}"""

    messages = [{"role": "system", "content": system_prompt}]
    if history:
        for turn in (history or [])[-10:]:
            if turn.get("role") in ("user", "assistant") and turn.get("content"):
                messages.append({"role": turn["role"], "content": turn["content"]})
    messages.append({"role": "user", "content": question})

    try:
        comp   = client.chat.completions.create(model=LLM_MODEL, messages=messages, max_tokens=400)
        answer = comp.choices[0].message.content.strip()
    except Exception as e:
        print(f"[Query] LLM error: {e}")
        answer = "Sorry, I couldn't process that query right now."
    return answer

# ── full pipeline ──────────────────────────────────────────────────────────────

def run_pipeline(save_path: str, filename: str, recording_id: int, device_id: str):
    base = os.path.splitext(filename)[0]
    print(f"\n{'='*60}")
    print(f"[Pipeline] {filename} | id={recording_id} | device={device_id}")

    try:
        print("[Pipeline] Step 1 — Converting to WAV...")
        wav_path = convert_to_wav(save_path)

        print("[Pipeline] Step 2 — VAD...")
        if not has_speech(wav_path):
            print("[Pipeline] No speech — skipping")
            db_update_status(recording_id, "no_speech")
            encrypt_file(wav_path)
            return

        print("[Pipeline] Step 3 — Diarizing patient voice...")
        filtered_wav, diarize_result = diarize_and_filter_patient(wav_path, device_id)
        speaker_label = diarize_result["label"]
        print(f"[Pipeline] Speaker: {speaker_label}")

        if speaker_label == "tv":
            db_update_status(recording_id, "tv_detected")
            return

        transcribe_path = filtered_wav

        print("[Pipeline] Step 4 — Transcribing...")
        transcript_text = transcribe(transcribe_path)
        if not transcript_text:
            db_update_status(recording_id, "transcription_failed")
            return
        print(f"[Pipeline] {len(transcript_text.split())} words")

        print("[Pipeline] Step 5 — Encrypting transcript...")
        t_path     = os.path.join(TRANSCRIPT_FOLDER, base + ".txt")
        with open(t_path, "w", encoding="utf-8") as f:
            f.write(transcript_text)
        enc_t      = encrypt_file(t_path)
        db_insert_transcript(recording_id, enc_t, device_id)
        db_update_status(recording_id, "transcribed")

        print("[Pipeline] Step 6 — Encrypting audio...")
        enc_wav = encrypt_file(wav_path)

        print("[Pipeline] Step 7 — Keyword check...")
        kw = keyword_check(transcript_text)
        if kw["danger"]:
            print(f"[Pipeline] ⚠️  Danger keywords: {kw['danger']}")
        if kw["forgetting"]:
            print(f"[Pipeline] ⚠️  Forgetting keywords: {kw['forgetting']}")

        print("[Pipeline] Step 8 — RAG indexing...")
        index_transcript(transcript_text, recording_id, device_id)

        print("[Pipeline] Step 9 — LLM danger/forgetting analysis...")
        analysis = llm_analyse(transcript_text, kw)
        print(f"[Pipeline] Danger={analysis.get('danger_detected')} Forgetting={analysis.get('forgetting_detected')}")

        print("[Pipeline] Step 10 — Intent extraction...")
        intents = extract_intents(transcript_text, recording_id, device_id)

        print("[Pipeline] Step 11 — Saving encrypted summary...")
        alert_needed = (
            analysis.get("alert_needed", False) or
            analysis.get("danger_detected", False) or
            analysis.get("forgetting_detected", False)
        )
        high_intents = [i for i in intents if i.get("decision") == "act"]

        summary_data = {
            "recording_id": recording_id, "device_id": device_id,
            "alert_needed": alert_needed, "keyword_check": kw,
            "speaker_label": speaker_label,
            "diarize_stats": diarize_result,
            "intents_extracted": len(intents),
            "high_confidence_intents": len(high_intents),
            "intent_summary": [
                {"task": i.get("task"), "temporal_cue": i.get("temporal_cue"),
                 "fused_confidence": i.get("fused_confidence"), "decision": i.get("decision"),
                 "scheduled_time": i.get("scheduled_time")}
                for i in intents
            ],
            **analysis,
        }
        s_path = os.path.join(SUMMARY_FOLDER, base + "_summary.json")
        with open(s_path, "w", encoding="utf-8") as f:
            json.dump(summary_data, f, indent=2)
        enc_s = encrypt_file(s_path)
        db_insert_summary(recording_id, enc_s, device_id)

        if alert_needed:
            db_update_status(recording_id, "alert_flagged")
            print(f"[Pipeline] 🚨 ALERT FLAGGED — id={recording_id}")
            if analysis.get("danger_detected"):
                print(f"[Pipeline] DANGER: {analysis.get('danger_details') or kw['danger']}")
            if analysis.get("forgetting_detected"):
                print(f"[Pipeline] FORGETTING: {analysis.get('forgetting_details') or kw['forgetting']}")
        elif high_intents:
            db_update_status(recording_id, "intent_flagged")
            print(f"[Pipeline] 📋 {len(high_intents)} high-confidence intent(s)")
        else:
            db_update_status(recording_id, "completed")
            print("[Pipeline] ✅ Completed")

    except Exception as e:
        print(f"[Pipeline] Error: {e}")
        db_update_status(recording_id, "error")

    print(f"[Pipeline] Done | {filename}")
    print(f"{'='*60}\n")

# ── routes ─────────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "mode": "dementia"}), 200

@app.route("/upload", methods=["POST"])
@require_auth
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    file      = request.files["file"]
    device_id = request.form.get("device_id", "").strip()
    if not device_id or device_id.lower() == "unknown":
        device_id = "patient_01"
    filename  = secure_filename(file.filename)
    save_path = os.path.join(AUDIO_FOLDER, filename)
    file.save(save_path)
    print(f"[Upload] {save_path} device={device_id}")
    try:
        recording_id = db_insert_recording(save_path, device_id)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    Thread(target=run_pipeline, args=(save_path, filename, recording_id, device_id)).start()
    return jsonify({"message": f"{filename} received", "recording_id": recording_id, "device_id": device_id}), 200

@app.route("/enroll/voice", methods=["POST"])
@require_auth
def enroll_voice():
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    file      = request.files["file"]
    device_id = request.form.get("device_id", "patient_01").strip()
    filename  = secure_filename(file.filename)
    save_path = os.path.join(ENROLL_FOLDER, filename)
    file.save(save_path)
    wav_path  = convert_to_wav(save_path)
    embedding = get_voice_embedding(wav_path)
    if embedding is None:
        return jsonify({"error": "Could not extract voice embedding"}), 500
    db_save_voice_profile(device_id, embedding)
    print(f"[VoiceID] ✅ Patient voice enrolled for device={device_id}")
    return jsonify({"message": f"Voice enrolled for {device_id}", "embedding_dim": int(embedding.shape[0])}), 200

@app.route("/recordings", methods=["GET"])
@require_auth
def list_recordings():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = """SELECT r.id,r.audio_file,r.status,r.created_at,r.device_id,
                              t.text,s.summary FROM recordings r
                       LEFT JOIN transcripts t ON t.recording_id=r.id
                       LEFT JOIN summaries   s ON s.recording_id=r.id"""
                params = []
                if device_id:
                    q += " WHERE r.device_id=%s"; params.append(device_id)
                q += " ORDER BY r.created_at DESC LIMIT 100;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"audio_file":r[1],"status":r[2],"created_at":str(r[3]),
                         "device_id":r[4],"transcript_path":r[5],"summary_path":r[6]} for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/alerts", methods=["GET"])
@require_auth
def get_alerts():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = """SELECT r.id,r.audio_file,r.created_at,r.device_id,s.summary
                       FROM recordings r JOIN summaries s ON s.recording_id=r.id
                       WHERE r.status IN ('alert_flagged','intent_flagged')"""
                params = []
                if device_id:
                    q += " AND r.device_id=%s"; params.append(device_id)
                q += " ORDER BY r.created_at DESC;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"audio_file":r[1],"created_at":str(r[2]),
                         "device_id":r[3],"summary_path":r[4]} for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/intents", methods=["GET"])
@require_auth
def get_intents():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = """SELECT id,recording_id,task,temporal_cue,fused_confidence,
                              decision,action,status,scheduled_time,device_id,created_at
                       FROM intents WHERE 1=1"""
                params = []
                if device_id:
                    q += " AND device_id=%s"; params.append(device_id)
                q += " ORDER BY created_at DESC LIMIT 100;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{
            "id":r[0],"recording_id":r[1],"task":r[2],"temporal_cue":r[3],
            "fused_confidence":r[4],"decision":r[5],"action":r[6],"status":r[7],
            "scheduled_time":str(r[8]) if r[8] else None,"device_id":r[9],"created_at":str(r[10]),
        } for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/intents/<int:intent_id>/feedback", methods=["POST"])
@require_auth
def intent_feedback(intent_id):
    try:
        outcome = request.get_json().get("outcome", "ignored")
        if outcome not in ("accepted", "rejected", "ignored"):
            return jsonify({"error": "outcome must be accepted, rejected or ignored"}), 400
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO intent_feedback (intent_id, outcome) VALUES (%s,%s);", (intent_id, outcome))
                cur.execute("UPDATE intents SET status=%s WHERE id=%s;", (outcome, intent_id))
        return jsonify({"message": f"Intent {intent_id} marked {outcome}"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/reminders/pending", methods=["GET"])
@require_auth
def get_pending_reminders():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = """SELECT id,recording_id,task,temporal_cue,fused_confidence,
                              decision,scheduled_time,device_id,created_at
                       FROM intents
                       WHERE reminder_sent=FALSE AND status='pending'
                         AND decision IN ('act','confirm')
                         AND (scheduled_time IS NULL OR scheduled_time <= NOW())"""
                params = []
                if device_id:
                    q += " AND device_id=%s"; params.append(device_id)
                q += " ORDER BY created_at ASC;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{
            "id":r[0],"recording_id":r[1],"task":r[2],"temporal_cue":r[3],
            "fused_confidence":r[4],"decision":r[5],
            "scheduled_time":str(r[6]) if r[6] else None,"device_id":r[7],"created_at":str(r[8]),
        } for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/reminders/<int:intent_id>/sent", methods=["POST"])
@require_auth
def mark_reminder_sent(intent_id):
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE intents SET reminder_sent=TRUE WHERE id=%s;", (intent_id,))
        return jsonify({"message": f"Reminder {intent_id} marked sent"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/caregiver/ask", methods=["POST"])
@require_auth
def caregiver_ask():
    data      = request.get_json()
    question  = data.get("question", "").strip()
    device_id = data.get("device_id", "patient_01").strip()
    history   = data.get("history", [])
    if not question:
        return jsonify({"error": "No question"}), 400
    answer = answer_caregiver_query(question, device_id, history)
    return jsonify({"question": question, "answer": answer, "device_id": device_id}), 200

@app.route("/decrypt/transcript/<int:recording_id>", methods=["GET"])
@require_auth
def get_transcript(recording_id):
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT text FROM transcripts WHERE recording_id=%s;", (recording_id,))
                row = cur.fetchone()
        if not row:
            return jsonify({"error": "Not found"}), 404
        if not os.path.exists(row[0]):
            return jsonify({"error": "File not found on disk"}), 404
        return jsonify({"recording_id": recording_id, "transcript": decrypt_file(row[0]).decode("utf-8")}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/decrypt/summary/<int:recording_id>", methods=["GET"])
@require_auth
def get_summary(recording_id):
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT summary FROM summaries WHERE recording_id=%s;", (recording_id,))
                row = cur.fetchone()
        if not row:
            return jsonify({"error": "Not found"}), 404
        if not os.path.exists(row[0]):
            return jsonify({"error": "File not found on disk"}), 404
        return jsonify({"recording_id": recording_id, "summary": json.loads(decrypt_file(row[0]).decode("utf-8"))}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/learning/stats", methods=["GET"])
@require_auth
def learning_stats():
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT i.decision, COUNT(*) as total,
                           SUM(CASE WHEN f.outcome='accepted' THEN 1 ELSE 0 END),
                           SUM(CASE WHEN f.outcome='rejected' THEN 1 ELSE 0 END),
                           ROUND(AVG(i.fused_confidence)::numeric, 3)
                    FROM intents i LEFT JOIN intent_feedback f ON f.intent_id=i.id
                    GROUP BY i.decision;
                """)
                rows = cur.fetchall()
        return jsonify([{
            "decision":r[0],"total":r[1],"accepted":r[2],
            "rejected":r[3],"avg_confidence":float(r[4]) if r[4] else 0,
        } for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/admin/tokens", methods=["POST"])
def create_token():
    if request.remote_addr not in ("127.0.0.1", "::1"):
        return jsonify({"error": "Localhost only"}), 403
    data      = request.get_json() or {}
    device_id = data.get("device_id", "patient_01")
    label     = data.get("label", "")
    raw_token = secrets.token_hex(32)
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO api_tokens (device_id, token_hash, label) VALUES (%s,%s,%s);",
                    (device_id, _hash_token(raw_token), label),
                )
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({"token": raw_token, "label": label, "note": "Save this — not shown again."}), 201

# ── run ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
