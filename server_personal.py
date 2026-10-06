import os
import re
import json
import wave
import struct
import tempfile
import subprocess
import hashlib
import secrets
from functools import wraps
import psycopg2
import numpy as np
import webrtcvad
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from threading import Thread
from groq import Groq
from cryptography.fernet import Fernet
from scipy.spatial.distance import cosine as cosine_distance
from dotenv import load_dotenv

# Load .env before importing config so env vars are available
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv("/home/osugiw/mcu_server/.env")

from config import (
    GROQ_API_KEY,
    DB_HOST, DB_NAME, DB_USER, DB_PASSWORD,
    AUDIO_FOLDER, TRANSCRIPT_FOLDER, SUMMARY_FOLDER,
    ENROLL_FOLDER, KEY_FILE,
)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024  # 50 MB max upload

# ── API token authentication ──────────────────────────────────────────────────

def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()

def require_auth(f):
    """Decorator — requires a valid Bearer token in the Authorization header."""
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
            print(f"[Auth] DB error: {exc}")
            return jsonify({"error": "Auth DB error"}), 500
        return f(*args, **kwargs)
    return decorated

# ── configuration ─────────────────────────────────────────────────────────────

# Folder paths come from config.py / env vars; defined here for clarity
for folder in [AUDIO_FOLDER, TRANSCRIPT_FOLDER, SUMMARY_FOLDER, ENROLL_FOLDER]:
    os.makedirs(folder, exist_ok=True)

# ── confidence fusion weights ─────────────────────────────────────────────────

WEIGHTS = {
    "semantic":  0.70,
    "temporal":  0.15,
    "cognitive": 0.15,
}

THRESHOLD_HIGH   = 0.75
THRESHOLD_MEDIUM = 0.50
THRESHOLD_LOW    = 0.30

HIGH_PRIORITY_TYPES = {"birthday", "appointment", "medication", "deadline", "emergency"}
ALWAYS_LOG_TYPES    = {"idea", "book", "recommendation", "observation"}

# ── Sally wake word ───────────────────────────────────────────────────────────

SALLY_TRIGGERS = ["hey sally", "ok sally", "hi sally", "sally"]

# ── voice ID config ───────────────────────────────────────────────────────────

# Cosine similarity threshold — below this = not the owner
VOICE_MATCH_THRESHOLD = 0.82

# Sub-window size for fine-grained speaker separation (milliseconds)
# Each VAD segment is split into these windows; only owner windows are kept.
# Shorter = more precise speaker switching, but less MFCC context per window.
DIARIZE_SUBWINDOW_MS = 500

# TV/video detection thresholds
# TV audio tends to be: high spectral flatness, multiple voices, consistent volume
TV_SPECTRAL_FLATNESS_THRESHOLD = 0.15   # TV audio is spectrally flat
TV_ZCR_THRESHOLD               = 0.12   # TV has high zero crossing rate
TV_ENERGY_VARIANCE_THRESHOLD   = 0.05   # TV audio has low energy variance (compressed)

# ── encryption setup ──────────────────────────────────────────────────────────

def load_or_create_key() -> Fernet:
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "rb") as f:
            key = f.read()
        print("[Encryption] Key loaded from disk.")
    else:
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as f:
            f.write(key)
        os.chmod(KEY_FILE, 0o600)
        print(f"[Encryption] New key generated → {KEY_FILE}")
        print("[Encryption] ⚠️  BACK UP THIS KEY FILE!")
    return Fernet(key)

FERNET = load_or_create_key()

def encrypt_file(input_path: str) -> str:
    with open(input_path, "rb") as f:
        data = f.read()
    encrypted = FERNET.encrypt(data)
    enc_path  = input_path + ".enc"
    with open(enc_path, "wb") as f:
        f.write(encrypted)
    os.remove(input_path)
    return enc_path

def decrypt_file(enc_path: str) -> bytes:
    with open(enc_path, "rb") as f:
        encrypted = f.read()
    return FERNET.decrypt(encrypted)

# ── Groq API setup ────────────────────────────────────────────────────────────

client        = Groq(api_key=GROQ_API_KEY)
LLM_MODEL     = "llama-3.3-70b-versatile"
WHISPER_MODEL = "whisper-large-v3"

# ── PostgreSQL config ─────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     DB_HOST,
    "dbname":   DB_NAME,
    "user":     DB_USER,
    "password": DB_PASSWORD,
}

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def init_db():
    schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    if not os.path.exists(schema_path):
        raise RuntimeError(
            f"schema.sql not found at {schema_path}. "
            "Run: psql -U jeeven -d stt_db -f schema.sql"
        )
    with get_db() as conn:
        with conn.cursor() as cur:
            with open(schema_path, "r", encoding="utf-8") as f:
                cur.execute(f.read())
        conn.commit()
    print("[DB] All tables initialised from schema.sql.")

# ── DB helpers ────────────────────────────────────────────────────────────────

def db_insert_recording(audio_path: str, device_id: str) -> int:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO recordings (audio_file, status, device_id) VALUES (%s,%s,%s) RETURNING id;",
                (audio_path, "uploaded", device_id)
            )
            return cur.fetchone()[0]

def db_insert_transcript(recording_id: int, path: str, device_id: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO transcripts (recording_id, text, device_id) VALUES (%s,%s,%s);",
                        (recording_id, path, device_id))

def db_insert_summary(recording_id: int, path: str, device_id: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO summaries (recording_id, summary, device_id) VALUES (%s,%s,%s);",
                        (recording_id, path, device_id))

def db_update_status(recording_id: int, status: str):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE recordings SET status=%s WHERE id=%s;", (status, recording_id))

def db_save_intent(recording_id: int, intent: dict, device_id: str) -> int:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO intents (
                    recording_id, task, intent_type, temporal_cue, raw_quote,
                    semantic_score, temporal_score, cognitive_score,
                    fused_confidence, decision, action,
                    cognitive_signals, status, scheduled_time, device_id
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id;
            """, (
                recording_id, intent.get("task",""), intent.get("intent_type","general"),
                intent.get("temporal_cue",""), intent.get("raw_quote",""),
                intent.get("semantic_score",0.0), intent.get("temporal_score",0.0),
                intent.get("cognitive_score",0.0), intent.get("fused_confidence",0.0),
                intent.get("decision","log"), intent.get("action","log_only"),
                json.dumps(intent.get("cognitive_signals",{})), "pending",
                intent.get("scheduled_time"), device_id,
            ))
            return cur.fetchone()[0]

def db_save_memory_chunk(recording_id: int, device_id: str, content: str, embedding: list):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO memory_chunks (recording_id, device_id, content, embedding)
                VALUES (%s,%s,%s,%s::vector);
            """, (recording_id, device_id, content, json.dumps(embedding)))

def db_search_memory(query_embedding: list, device_id: str, limit: int = 5) -> list:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT content, created_at,
                       1 - (embedding <=> %s::vector) AS similarity
                FROM memory_chunks
                WHERE device_id = %s
                ORDER BY embedding <=> %s::vector
                LIMIT %s;
            """, (json.dumps(query_embedding), device_id, json.dumps(query_embedding), limit))
            return cur.fetchall()

def db_save_sally_query(device_id, recording_id, question, answer, source_chunks, context):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO sally_queries
                (device_id, recording_id, question, answer, source_chunks, transcript_context)
                VALUES (%s,%s,%s,%s,%s,%s);
            """, (device_id, recording_id, question, answer, source_chunks, context))

def db_save_voice_profile(device_id: str, embedding: np.ndarray):
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM voice_profiles WHERE device_id=%s;", (device_id,))
            cur.execute("""
                INSERT INTO voice_profiles (device_id, label, embedding)
                VALUES (%s,'owner',%s);
            """, (device_id, json.dumps(embedding.tolist())))

def db_get_voice_profile(device_id: str) -> np.ndarray | None:
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT embedding FROM voice_profiles WHERE device_id=%s LIMIT 1;", (device_id,))
            row = cur.fetchone()
    if row:
        emb = row[0]
        return np.array(json.loads(emb) if isinstance(emb, str) else emb)
    return None

# ── audio conversion ──────────────────────────────────────────────────────────

def convert_to_wav(input_path: str, target_sr: int = 16000) -> str:
    ext = os.path.splitext(input_path)[1].lower()
    if ext == ".wav":
        return input_path
    wav_path = os.path.splitext(input_path)[0] + ".wav"
    print(f"[Pipeline] Converting {ext} → WAV ...")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", input_path,
         "-ar", str(target_sr), "-ac", "1", "-sample_fmt", "s16", wav_path],
        capture_output=True, text=True
    )
    if result.returncode != 0 or not os.path.exists(wav_path):
        print(f"[Pipeline] FFmpeg error: {result.stderr}")
        return input_path
    print(f"[Pipeline] Converted → {wav_path}")
    return wav_path

# ── load raw audio samples from WAV ──────────────────────────────────────────

def load_wav_samples(wav_path: str) -> tuple[np.ndarray, int]:
    """Load WAV file and return (samples as float32, sample_rate)."""
    with wave.open(wav_path, "rb") as wf:
        sr     = wf.getframerate()
        nch    = wf.getnchannels()
        sw     = wf.getsampwidth()
        nf     = wf.getnframes()
        raw    = wf.readframes(nf)

    # Convert to numpy float32
    if sw == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sw == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        samples = np.frombuffer(raw, dtype=np.uint8).astype(np.float32) / 128.0 - 1.0

    # Mix down to mono
    if nch > 1:
        samples = samples.reshape(-1, nch).mean(axis=1)

    return samples, sr

# ── voice activity detection ──────────────────────────────────────────────────

def has_speech(wav_path: str, aggressiveness: int = 2, min_ratio: float = 0.1) -> bool:
    try:
        vad = webrtcvad.Vad(aggressiveness)
        with wave.open(wav_path, "rb") as wf:
            sr  = wf.getframerate()
            nch = wf.getnchannels()
            sw  = wf.getsampwidth()
            if sr not in (8000, 16000, 32000, 48000) or nch != 1 or sw != 2:
                print("[VAD] Format not ideal — assuming speech")
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

# ── TV / video detection ──────────────────────────────────────────────────────

def detect_tv_audio(samples: np.ndarray, sr: int) -> dict:
    """
    Detect if audio is from a TV/video rather than live speech.

    TV audio characteristics:
    - High spectral flatness (noise-like spectrum from compression)
    - Consistent energy (broadcast audio is heavily compressed/normalised)
    - Multiple overlapping voices with no natural pause patterns
    - Higher zero crossing rate from audio processing artifacts

    Returns dict with is_tv bool and confidence score.
    """
    if len(samples) < sr:
        return {"is_tv": False, "confidence": 0.0, "reason": "Too short to analyse"}

    # ── Feature 1: Spectral flatness ─────────────────────────────────────────
    # TV audio is spectrally flat (compressed), live speech has peaks
    frame_size = 512
    flatness_scores = []
    for i in range(0, len(samples) - frame_size, frame_size):
        frame    = samples[i:i+frame_size]
        spectrum = np.abs(np.fft.rfft(frame * np.hanning(frame_size)))
        spectrum = spectrum + 1e-10
        geo_mean = np.exp(np.mean(np.log(spectrum)))
        ari_mean = np.mean(spectrum)
        flatness = geo_mean / ari_mean
        flatness_scores.append(flatness)
    avg_flatness = np.mean(flatness_scores)

    # ── Feature 2: Energy variance ────────────────────────────────────────────
    # TV audio has low energy variance (heavily compressed)
    # Live speech has high variance (pauses, emphasis)
    hop = sr // 10   # 100ms hops
    energies = [
        np.sqrt(np.mean(samples[i:i+hop]**2))
        for i in range(0, len(samples) - hop, hop)
    ]
    energy_variance = np.var(energies) / (np.mean(energies) + 1e-10)

    # ── Feature 3: Zero crossing rate ─────────────────────────────────────────
    # TV audio tends to have higher ZCR due to audio processing
    zcr = np.mean(np.abs(np.diff(np.sign(samples)))) / 2

    # ── Feature 4: Pause pattern ──────────────────────────────────────────────
    # Live speech has natural pauses, TV has continuous audio
    silence_threshold = 0.01
    silence_frames    = np.sum(np.abs(samples) < silence_threshold) / len(samples)
    # Live speech typically 20-40% silence, TV < 10%
    natural_pauses = silence_frames > 0.15

    print(f"[TVDetect] spectral_flatness={avg_flatness:.3f} "
          f"energy_variance={energy_variance:.3f} "
          f"zcr={zcr:.3f} "
          f"silence_ratio={silence_frames:.3f}")

    # ── Decision ──────────────────────────────────────────────────────────────
    tv_signals = 0
    reasons    = []

    if avg_flatness > TV_SPECTRAL_FLATNESS_THRESHOLD:
        tv_signals += 1
        reasons.append(f"high spectral flatness ({avg_flatness:.3f})")

    if energy_variance < TV_ENERGY_VARIANCE_THRESHOLD:
        tv_signals += 1
        reasons.append(f"low energy variance ({energy_variance:.3f})")

    if zcr > TV_ZCR_THRESHOLD:
        tv_signals += 1
        reasons.append(f"high ZCR ({zcr:.3f})")

    if not natural_pauses:
        tv_signals += 1
        reasons.append(f"no natural pauses ({silence_frames:.2%} silence)")

    tv_confidence = tv_signals / 4.0
    is_tv         = tv_signals >= 3   # 3 out of 4 signals = TV

    result = {
        "is_tv":      is_tv,
        "confidence": round(tv_confidence, 2),
        "signals":    tv_signals,
        "reason":     ", ".join(reasons) if reasons else "live speech",
        "features": {
            "spectral_flatness": round(float(avg_flatness), 3),
            "energy_variance":   round(float(energy_variance), 3),
            "zcr":               round(float(zcr), 3),
            "silence_ratio":     round(float(silence_frames), 3),
        }
    }

    if is_tv:
        print(f"[TVDetect] 📺 TV/VIDEO detected (confidence={tv_confidence:.0%}) — {', '.join(reasons)}")
    else:
        print(f"[TVDetect] 🎤 Live speech detected (tv_confidence={tv_confidence:.0%})")

    return result

# ── MFCC voice embedding ──────────────────────────────────────────────────────

def compute_mfcc_embedding(samples: np.ndarray, sr: int,
                           n_mfcc: int = 40, n_fft: int = 512,
                           hop_length: int = 160) -> np.ndarray:
    """
    Compute MFCC-based voice embedding using pure numpy/scipy.
    Returns a 120-dim embedding: mean + std + delta-mean of 40 MFCCs.
    Works on Pi 4 ARM — no torch/resemblyzer needed.
    """
    from scipy.fft import dct

    # Pre-emphasis
    pre_emphasis = 0.97
    samples      = np.append(samples[0], samples[1:] - pre_emphasis * samples[:-1])

    # Frame the signal
    frame_length = n_fft
    frames       = []
    for i in range(0, len(samples) - frame_length, hop_length):
        frame = samples[i:i+frame_length] * np.hanning(frame_length)
        frames.append(frame)

    if not frames:
        return np.zeros(n_mfcc * 3)

    frames = np.array(frames)

    # Power spectrum
    power_spectrum = (np.abs(np.fft.rfft(frames, n=n_fft)) ** 2) / n_fft

    # Mel filterbank
    n_mels   = 40
    fmin     = 0
    fmax     = sr // 2
    mel_low  = 2595 * np.log10(1 + fmin / 700)
    mel_high = 2595 * np.log10(1 + fmax / 700)
    mel_pts  = np.linspace(mel_low, mel_high, n_mels + 2)
    hz_pts   = 700 * (10 ** (mel_pts / 2595) - 1)
    bin_pts  = np.floor((n_fft + 1) * hz_pts / sr).astype(int)

    filterbank = np.zeros((n_mels, n_fft // 2 + 1))
    for m in range(1, n_mels + 1):
        f_m_minus = bin_pts[m - 1]
        f_m       = bin_pts[m]
        f_m_plus  = bin_pts[m + 1]
        for k in range(f_m_minus, f_m):
            if f_m != f_m_minus:
                filterbank[m-1, k] = (k - f_m_minus) / (f_m - f_m_minus)
        for k in range(f_m, f_m_plus):
            if f_m_plus != f_m:
                filterbank[m-1, k] = (f_m_plus - k) / (f_m_plus - f_m)

    # Apply filterbank and log
    mel_energy = np.dot(power_spectrum, filterbank.T)
    mel_energy = np.where(mel_energy == 0, np.finfo(float).eps, mel_energy)
    log_mel    = np.log(mel_energy)

    # DCT to get MFCCs
    mfccs = dct(log_mel, type=2, axis=1, norm='ortho')[:, :n_mfcc]

    # Compute statistics: mean, std, delta-mean
    mfcc_mean  = np.mean(mfccs, axis=0)       # shape (n_mfcc,)
    mfcc_std   = np.std(mfccs, axis=0)        # shape (n_mfcc,)

    # Delta (first derivative)
    delta = np.diff(mfccs, axis=0)
    delta_mean = np.mean(delta, axis=0) if len(delta) > 0 else np.zeros(n_mfcc)

    # Concatenate → 120-dim embedding
    embedding = np.concatenate([mfcc_mean, mfcc_std, delta_mean])

    # L2 normalise
    norm = np.linalg.norm(embedding)
    if norm > 0:
        embedding = embedding / norm

    return embedding

def get_voice_embedding(wav_path: str) -> np.ndarray | None:
    """Extract MFCC voice embedding from WAV file."""
    try:
        samples, sr = load_wav_samples(wav_path)
        if len(samples) < sr:   # need at least 1 second
            print("[VoiceID] Audio too short for embedding")
            return None
        embedding = compute_mfcc_embedding(samples, sr)
        print(f"[VoiceID] Embedding computed: {embedding.shape[0]}-dim MFCC")
        return embedding
    except Exception as e:
        print(f"[VoiceID] Embedding error: {e}")
        return None

def identify_speaker(wav_path: str, device_id: str) -> dict:
    """
    Identify speaker as owner, other, or tv.
    Returns dict with label, confidence and method.
    """
    # Load samples for TV detection
    try:
        samples, sr = load_wav_samples(wav_path)
    except Exception as e:
        print(f"[VoiceID] Could not load samples: {e}")
        return {"label": "unknown", "confidence": 0.0, "method": "error"}

    # ── Step 1: TV detection first ────────────────────────────────────────────
    tv_result = detect_tv_audio(samples, sr)
    if tv_result["is_tv"]:
        return {
            "label":      "tv",
            "confidence": tv_result["confidence"],
            "method":     "spectral_analysis",
            "tv_details": tv_result,
        }

    # ── Step 2: Voice profile comparison ─────────────────────────────────────
    profile = db_get_voice_profile(device_id)
    if profile is None:
        print("[VoiceID] No voice profile enrolled — labelling as 'other'")
        return {"label": "other", "confidence": 0.0, "method": "no_profile"}

    embedding = get_voice_embedding(wav_path)
    if embedding is None:
        return {"label": "unknown", "confidence": 0.0, "method": "embedding_failed"}

    # Cosine similarity (1 - cosine_distance)
    similarity = float(1.0 - cosine_distance(profile, embedding))
    is_owner   = similarity >= VOICE_MATCH_THRESHOLD

    label = "owner" if is_owner else "other"
    print(f"[VoiceID] Speaker={label} similarity={similarity:.3f} threshold={VOICE_MATCH_THRESHOLD}")

    return {
        "label":      label,
        "confidence": round(similarity, 3),
        "method":     "mfcc_cosine",
        "similarity": round(similarity, 3),
    }


def diarize_and_filter_owner(wav_path: str, device_id: str,
                              min_segment_ms: int = 800) -> tuple:
    """
    Split audio into VAD speech segments, classify each against the owner
    voiceprint, and write a new WAV containing only owner segments.

    Returns (filtered_wav_path, stats_dict).
    If no profile is enrolled, returns (wav_path, {"label": "unknown"}).
    """
    try:
        samples, sr = load_wav_samples(wav_path)
    except Exception as e:
        print(f"[Diarize] Could not load audio: {e}")
        return wav_path, {"label": "unknown", "owner_segments": 0, "total_segments": 0}

    # TV check first — no point diarizing broadcast audio
    tv_result = detect_tv_audio(samples, sr)
    if tv_result["is_tv"]:
        return wav_path, {"label": "tv", "owner_segments": 0, "total_segments": 0}

    profile = db_get_voice_profile(device_id)
    if profile is None:
        print("[Diarize] No voice profile — processing full audio as unknown")
        return wav_path, {"label": "unknown", "owner_segments": 0, "total_segments": 0}

    # ── VAD segmentation ──────────────────────────────────────────────────────
    pcm16      = (samples * 32768).astype(np.int16)
    frame_ms   = 30
    frame_samp = int(sr * frame_ms / 1000)
    vad        = webrtcvad.Vad(2)

    raw_segments = []
    in_speech    = False
    seg_start    = 0
    for i in range(0, len(pcm16) - frame_samp, frame_samp):
        frame = pcm16[i:i + frame_samp].tobytes()
        try:
            is_s = vad.is_speech(frame, sr)
        except Exception:
            continue
        if is_s and not in_speech:
            seg_start = i
            in_speech = True
        elif not is_s and in_speech:
            raw_segments.append((seg_start, i))
            in_speech = False
    if in_speech:
        raw_segments.append((seg_start, len(pcm16)))

    # Merge gaps < 500 ms
    merge_gap = int(sr * 0.5)
    merged = []
    for s, e in raw_segments:
        if merged and s - merged[-1][1] < merge_gap:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))

    # Drop segments shorter than min_segment_ms
    min_samp = int(sr * min_segment_ms / 1000)
    merged   = [(s, e) for s, e in merged if e - s >= min_samp]

    total = len(merged)
    print(f"[Diarize] {total} speech segment(s) found")

    # ── Sub-window owner classification ──────────────────────────────────────
    # Each VAD segment is sliced into DIARIZE_SUBWINDOW_MS windows.
    # Only windows where the embedding is close to the owner profile are kept.
    # This handles conversations where two people alternate rapidly.
    sub_size    = int(sr * DIARIZE_SUBWINDOW_MS / 1000)
    owner_parts = []
    total_windows = 0
    owner_windows = 0

    for s, e in merged:
        seg = samples[s:e]
        seg_kept = []
        for i in range(0, len(seg) - sub_size + 1, sub_size):
            window = seg[i:i + sub_size]
            total_windows += 1
            try:
                emb = compute_mfcc_embedding(window, sr)
                sim = float(1.0 - cosine_distance(profile, emb))
                if sim >= VOICE_MATCH_THRESHOLD:
                    seg_kept.append(window)
                    owner_windows += 1
            except Exception as exc:
                print(f"[Diarize]  ⚠️  sub-window embed error: {exc}")

        owner_frac = len(seg_kept) / max(1, len(seg) // sub_size)
        label = "✅" if seg_kept else "❌"
        print(f"[Diarize]  {label} seg {(e-s)/sr:.1f}s — {len(seg_kept)}/{max(1, len(seg)//sub_size)} windows kept ({owner_frac:.0%})")
        owner_parts.extend(seg_kept)

    print(f"[Diarize] {owner_windows}/{total_windows} sub-windows kept across {total} segment(s)")

    if not owner_parts:
        return wav_path, {"label": "other", "owner_segments": 0, "total_segments": total}

    # ── Concatenate owner sub-windows → new WAV ───────────────────────────────
    silence_pad  = np.zeros(int(sr * 0.1), dtype=np.float32)
    interleaved  = []
    for part in owner_parts:
        interleaved.append(part)
        interleaved.append(silence_pad)
    filtered     = np.concatenate(interleaved)
    pcm_filtered = (filtered * 32768).astype(np.int16)

    filtered_path = wav_path.replace(".wav", "_owner.wav")
    with wave.open(filtered_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm_filtered.tobytes())

    return filtered_path, {
        "label":            "owner",
        "owner_segments":   owner_windows,
        "total_segments":   total_windows,
        "avg_similarity":   round(owner_windows / max(1, total_windows), 3),
        "owner_duration_s": round(len(filtered) / sr, 1),
    }


# ── Groq Whisper STT ──────────────────────────────────────────────────────────

def transcribe_groq(wav_path: str) -> str:
    print(f"[STT] Sending to Groq Whisper ({WHISPER_MODEL})...")
    try:
        with open(wav_path, "rb") as f:
            transcription = client.audio.transcriptions.create(
                file=(os.path.basename(wav_path), f),
                model=WHISPER_MODEL,
                response_format="text",
                language="en",
            )
        text = str(transcription).strip()
        print(f"[STT] Transcribed: {text[:120]}...")
        return text
    except Exception as e:
        print(f"[STT] Groq Whisper error: {e}")
        return ""

# ── RAG memory ────────────────────────────────────────────────────────────────

def get_text_embedding(text: str) -> list | None:
    """
    Pure numpy hash-based bag-of-words embedding.
    Works on Pi 4 ARM — no torch/transformers needed.
    Uses unigrams + bigrams hashed into a 384-dim vector.
    """
    try:
        import hashlib
        words     = re.findall(r"\b\w+\b", text.lower())
        embedding = np.zeros(384)
        # Unigrams
        for word in words:
            h = int(hashlib.md5(word.encode()).hexdigest(), 16) % 384
            embedding[h] += 1.0
        # Bigrams — improves phrase matching
        for i in range(len(words) - 1):
            bigram = words[i] + "_" + words[i+1]
            h = int(hashlib.md5(bigram.encode()).hexdigest(), 16) % 384
            embedding[h] += 0.5
        # L2 normalise
        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm
        return embedding.tolist()
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
    chunks = chunk_text(transcript)
    print(f"[RAG] Indexing {len(chunks)} chunk(s)...")
    indexed = 0
    for chunk in chunks:
        embedding = get_text_embedding(chunk)
        if embedding:
            db_save_memory_chunk(recording_id, device_id, chunk, embedding)
            indexed += 1
    print(f"[RAG] Indexed {indexed}/{len(chunks)} chunk(s) for device={device_id}")

def retrieve_context(question: str, device_id: str, limit: int = 5) -> list:
    embedding = get_text_embedding(question)
    if not embedding:
        return []
    return db_search_memory(embedding, device_id, limit)

# ── Sally wake word + Q&A ─────────────────────────────────────────────────────

def detect_sally_queries(transcript: str) -> list:
    text_lower = transcript.lower()
    queries    = []
    for trigger in SALLY_TRIGGERS:
        idx = 0
        while True:
            pos = text_lower.find(trigger, idx)
            if pos == -1:
                break
            after = transcript[pos + len(trigger):pos + len(trigger) + 200].strip()
            end   = len(after)
            for sep in ["?", ".", "!", "\n"] + SALLY_TRIGGERS:
                sp = after.lower().find(sep)
                if sp != -1 and sp < end:
                    end = sp + 1
            question = after[:end].strip(" .,")
            if question and len(question) > 3:
                queries.append(question)
            idx = pos + 1
    return queries

def answer_sally_query(question: str, device_id: str,
                       recording_id, transcript_context: str,
                       history: list = None) -> str:
    print(f"\n[Sally] Question: '{question}'")
    context_chunks = retrieve_context(question, device_id)

    if context_chunks:
        context_text = "\n\n".join([
            f"[{str(row[1])[:16]}] {row[0]}" for row in context_chunks
        ])
        print(f"[Sally] {len(context_chunks)} relevant memory chunk(s) retrieved")
    else:
        context_text = "No relevant past context found."

    source_summary = json.dumps([
        {"preview": row[0][:80], "similarity": round(float(row[2]), 3)}
        for row in context_chunks
    ])

    system_prompt = f"""You are Sally, a personal AI assistant embedded in a wearable device worn by the person you are speaking with.
Always address them directly using "you" and "your" — never say "the user" or "the speaker".
Answer concisely and helpfully. If the answer is in the memory context, use it.
If not, answer from general knowledge and briefly say so.
Keep answers to 2-3 sentences unless more detail is clearly needed.

--- LONG-TERM MEMORY (relevant past recordings) ---
{context_text}"""

    messages = [{"role": "system", "content": system_prompt}]

    # Inject prior turns from this session (last 10 turns to stay within token limits)
    if history:
        for turn in history[-10:]:
            role = turn.get("role", "")
            content = turn.get("content", "")
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})

    messages.append({"role": "user", "content": question})

    try:
        completion = client.chat.completions.create(
            model=LLM_MODEL,
            messages=messages,
            max_tokens=400,
        )
        answer = completion.choices[0].message.content.strip()
    except Exception as e:
        print(f"[Sally] LLM error: {e}")
        answer = "Sorry, I couldn't process that question right now."

    print(f"[Sally] Answer: {answer}")
    db_save_sally_query(device_id, recording_id, question, answer,
                        source_summary, transcript_context[:1000])
    return answer

# ── cognitive signals ─────────────────────────────────────────────────────────

FILLER_WORDS   = ["uh","um","er","ah","like","you know","i mean","so","well","basically","actually"]
TEMPORAL_WORDS = ["later","tomorrow","tonight","today","afternoon","morning","evening","next week","soon","at","by"]

def cognitive_signals(text: str) -> dict:
    words          = text.lower().split()
    total          = len(words) if words else 1
    fillers        = sum(1 for w in words if w in FILLER_WORDS)
    density        = round(fillers / total, 3)
    phrases        = [" ".join(words[i:i+3]) for i in range(len(words)-2)]
    repeated       = len(phrases) - len(set(phrases))
    hesitation     = min(1.0, round(density * 3 + repeated / total, 3))
    return {"filler_count": fillers, "filler_density": density,
            "repeated_phrases": repeated, "hesitation_score": hesitation}

def temporal_score(text: str) -> float:
    found    = [t for t in TEMPORAL_WORDS if t in text.lower()]
    if not found: return 0.0
    specific = [t for t in found if t in ["at","by","tomorrow","tonight","next week"]]
    return min(1.0, round(0.4 + len(specific)*0.2 + len(found)*0.1, 2))

def parse_scheduled_time(cue: str):
    if not cue: return None
    now = datetime.now()
    c   = cue.lower().strip()
    if "tonight" in c or "this evening" in c: return now.replace(hour=19,minute=0,second=0,microsecond=0)
    if "tomorrow morning" in c: return (now+timedelta(days=1)).replace(hour=9,minute=0,second=0,microsecond=0)
    if "tomorrow" in c: return (now+timedelta(days=1)).replace(hour=9,minute=0,second=0,microsecond=0)
    if "afternoon" in c: return now.replace(hour=14,minute=0,second=0,microsecond=0)
    if "morning" in c: return now.replace(hour=9,minute=0,second=0,microsecond=0)
    if "next week" in c: return now+timedelta(weeks=1)
    if "later" in c or "soon" in c: return now+timedelta(hours=2)
    m = re.search(r"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", c)
    if m:
        h = int(m.group(1)); mn = int(m.group(2) or 0); ap = m.group(3)
        if ap=="pm" and h!=12: h+=12
        elif ap=="am" and h==12: h=0
        s = now.replace(hour=h,minute=mn,second=0,microsecond=0)
        if s < now: s += timedelta(days=1)
        return s
    return None

def fuse_confidence(semantic, temporal, cognitive) -> float:
    h   = cognitive.get("hesitation_score", 0.0)
    cog = round(max(0.3, 1.0 - h*0.7), 3)
    return round(min(1.0, WEIGHTS["semantic"]*semantic + WEIGHTS["temporal"]*temporal + WEIGHTS["cognitive"]*cog), 3)

def decide(fused: float, itype: str = "general") -> dict:
    t = itype.lower().strip()
    if t in HIGH_PRIORITY_TYPES:
        if fused >= 0.45: return {"decision":"act",     "action":"notify",   "description":f"✅ HIGH ({t})"}
        if fused >= 0.25: return {"decision":"confirm", "action":"flag",     "description":f"⚠️  MEDIUM ({t})"}
        return                    {"decision":"log",     "action":"log_only", "description":"🔹 LOW"}
    if t in ALWAYS_LOG_TYPES:
        return {"decision":"log","action":"log_only","description":f"🔹 LOG ({t})"}
    if fused >= THRESHOLD_HIGH:   return {"decision":"act",     "action":"notify",   "description":"✅ HIGH"}
    if fused >= THRESHOLD_MEDIUM: return {"decision":"confirm", "action":"flag",     "description":"⚠️  MEDIUM"}
    if fused >= THRESHOLD_LOW:    return {"decision":"log",     "action":"log_only", "description":"🔹 LOW"}
    return                               {"decision":"ignore",  "action":"none",     "description":"❌ IGNORE"}

def extract_intents(transcript: str, recording_id: int, device_id: str) -> list:
    cog = cognitive_signals(transcript)
    prompt = f"""Extract every task, reminder or intention from this transcript.

For each:
- task: clean description
- intent_type: lowercase label (reminder, grocery, call, appointment, medication, idea, etc.)
- temporal_cue: time reference or empty string
- semantic_score: 0.0-1.0
- raw_quote: exact words

Do NOT extract Sally questions.
Return empty list if nothing found.
Respond ONLY in valid JSON: {{"intents":[{{"task":"","intent_type":"","temporal_cue":"","semantic_score":0.0,"raw_quote":""}}]}}

Cognitive: filler_density={cog['filler_density']} hesitation={cog['hesitation_score']}

Transcript:
{transcript}"""

    try:
        comp = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role":"user","content":prompt}],
            response_format={"type":"json_object"}
        )
        raw = json.loads(comp.choices[0].message.content).get("intents",[])
        out = []
        for intent in raw:
            semantic = float(intent.get("semantic_score",0.0))
            cue      = intent.get("temporal_cue","")
            itype    = intent.get("intent_type","general").lower().strip()
            temp     = temporal_score(cue+" "+intent.get("task",""))
            fused    = fuse_confidence(semantic, temp, cog)
            dec      = decide(fused, itype)
            sched    = parse_scheduled_time(cue)

            fi = {
                "task": intent.get("task",""), "intent_type": itype,
                "temporal_cue": cue, "raw_quote": intent.get("raw_quote",""),
                "semantic_score": round(semantic,3), "temporal_score": round(temp,3),
                "cognitive_score": round(max(0.3,1.0-cog["hesitation_score"]*0.7),3),
                "fused_confidence": fused, "decision": dec["decision"],
                "action": dec["action"], "cognitive_signals": cog,
                "scheduled_time": sched.isoformat() if sched else None,
            }
            fi["id"] = db_save_intent(recording_id, fi, device_id)
            out.append(fi)
            print(f"[Intent] {dec['description']} [{itype.upper()}] '{fi['task']}'")
        if not out: print("[Intent] No intents detected.")
        return out
    except Exception as e:
        print(f"[Intent Error] {e}")
        return []

def summarise_transcript(transcript: str) -> dict:
    prompt = f"""Summarise this personal recording. Address the owner directly using "you" (second person) — never say "the user" or "the speaker".
Respond ONLY in valid JSON:
{{"headline":"one sentence","summary":"2-3 sentences","topics":[],"mood":"one word",
"action_items":[],"people_mentioned":[],"notable_quotes":[]}}

Transcript:
{transcript}"""
    try:
        comp   = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role":"user","content":prompt}],
            response_format={"type":"json_object"}
        )
        result = json.loads(comp.choices[0].message.content)
        print(f"[Summary] {result.get('headline','N/A')} | mood={result.get('mood','?')}")
        return result
    except Exception as e:
        print(f"[Summary Error] {e}")
        return {"headline":"Summary unavailable","summary":"","topics":[],
                "mood":"unknown","action_items":[],"people_mentioned":[],"notable_quotes":[]}

# ── full pipeline ─────────────────────────────────────────────────────────────

def run_pipeline(save_path: str, filename: str, recording_id: int, device_id: str):
    base_name = os.path.splitext(filename)[0]
    print(f"\n{'='*60}")
    print(f"[Pipeline] {filename} | id={recording_id} | device={device_id}")

    try:
        # Step 1 — Convert
        print("[Pipeline] Step 1 — Converting to WAV...")
        wav_path = convert_to_wav(save_path)

        # Step 2 — VAD
        print("[Pipeline] Step 2 — VAD...")
        if not has_speech(wav_path):
            print("[Pipeline] No speech — skipping")
            db_update_status(recording_id, "no_speech")
            encrypt_file(wav_path)
            return

        # Step 3 — Diarize: filter audio to owner-only segments
        print("[Pipeline] Step 3 — Diarizing + filtering owner voice...")
        filtered_wav, diarize_result = diarize_and_filter_owner(wav_path, device_id)
        speaker_label = diarize_result["label"]
        print(f"[Pipeline] Speaker: {speaker_label} | "
              f"segments={diarize_result.get('owner_segments',0)}/"
              f"{diarize_result.get('total_segments',0)}")

        if speaker_label == "tv":
            print("[Pipeline] 📺 TV audio detected — skipping")
            db_update_status(recording_id, "tv_audio")
            encrypt_file(wav_path)
            return

        if speaker_label == "other":
            print("[Pipeline] No owner voice detected — skipping")
            db_update_status(recording_id, "no_owner_speech")
            encrypt_file(wav_path)
            return

        # Use filtered (owner-only) audio for transcription
        if filtered_wav != wav_path:
            print(f"[Pipeline] Owner audio: {diarize_result.get('owner_duration_s',0)}s "
                  f"(avg sim={diarize_result.get('avg_similarity',0):.3f})")
        transcribe_path = filtered_wav

        # Step 4 — Groq Whisper STT
        print("[Pipeline] Step 4 — Transcribing via Groq Whisper...")
        transcript_text = transcribe_groq(transcribe_path)

        if not transcript_text.strip():
            print("[Pipeline] Empty transcript")
            db_update_status(recording_id, "transcription_failed")
            return

        word_count = len(transcript_text.split())
        print(f"[Pipeline] {word_count} words | speaker={speaker_label}")

        # Step 5 — Save encrypted transcript
        print("[Pipeline] Step 5 — Encrypting transcript...")
        tp  = os.path.join(TRANSCRIPT_FOLDER, base_name + ".txt")
        with open(tp, "w", encoding="utf-8") as f:
            f.write(transcript_text)
        etp = encrypt_file(tp)
        db_insert_transcript(recording_id, etp, device_id)
        db_update_status(recording_id, "transcribed")

        # Step 6 — Encrypt audio
        print("[Pipeline] Step 6 — Encrypting audio...")
        eap = encrypt_file(wav_path)

        # Step 7 — Index into RAG memory (background)
        print("[Pipeline] Step 7 — Indexing into RAG memory...")
        Thread(target=index_transcript, args=(transcript_text, recording_id, device_id)).start()

        # Step 8 — Sally queries
        print("[Pipeline] Step 8 — Checking for Sally queries...")
        sally_qs = detect_sally_queries(transcript_text)
        sally_qa = []
        if sally_qs:
            print(f"[Pipeline] {len(sally_qs)} Sally query/queries")
            for q in sally_qs:
                ans = answer_sally_query(q, device_id, recording_id, transcript_text)
                sally_qa.append({"question": q, "answer": ans})
        else:
            print("[Pipeline] No Sally queries")

        # Step 9 — Summarise (only for owner's audio)
        print("[Pipeline] Step 9 — Summarising...")
        summary_result = summarise_transcript(transcript_text) if speaker_label == "owner" \
                         else {"headline": "Other speaker — not summarised", "summary": "",
                               "topics": [], "mood": "unknown", "action_items": [],
                               "people_mentioned": [], "notable_quotes": []}

        # Step 10 — Intent extraction (only for owner)
        print("[Pipeline] Step 10 — Intent extraction...")
        intents = extract_intents(transcript_text, recording_id, device_id) \
                  if speaker_label in ("owner", "unknown") else []
        high_conf = [i for i in intents if i.get("decision") == "act"]

        # Step 11 — Save encrypted summary
        print("[Pipeline] Step 11 — Saving summary...")
        summary_data = {
            "recording_id": recording_id, "device_id": device_id,
            "speaker": speaker_label, "speaker_confidence": diarize_result.get("avg_similarity",0),
            "word_count": word_count, "transcript_file": etp, "audio_file": eap,
            "intents_extracted": len(intents), "high_confidence_intents": len(high_conf),
            "sally_queries": len(sally_qa), "sally_qa": sally_qa,
            "intent_summary": [
                {"task": i.get("task"), "intent_type": i.get("intent_type"),
                 "temporal_cue": i.get("temporal_cue"), "fused_confidence": i.get("fused_confidence"),
                 "decision": i.get("decision"), "scheduled_time": i.get("scheduled_time")}
                for i in intents
            ],
            **summary_result,
        }
        sp  = os.path.join(SUMMARY_FOLDER, base_name + "_summary.json")
        with open(sp, "w", encoding="utf-8") as f:
            json.dump(summary_data, f, indent=2)
        esp = encrypt_file(sp)
        db_insert_summary(recording_id, esp, device_id)

        # Step 12 — Status
        if high_conf:
            db_update_status(recording_id, "intent_flagged")
            print(f"[Pipeline] 📋 {len(high_conf)} high-confidence intent(s)")
        else:
            db_update_status(recording_id, "completed")
            print("[Pipeline] ✅ Completed")

    except Exception as e:
        import traceback
        print(f"[Pipeline] Error: {e}")
        traceback.print_exc()
        db_update_status(recording_id, "error")

    print(f"[Pipeline] Done | {filename}")
    print(f"{'='*60}\n")

# ── routes ────────────────────────────────────────────────────────────────────

@app.route("/", methods=["GET"])
def index_route():
    return "Sally Personal Assistant Server is running!"

@app.route("/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "No filename"}), 400
    device_id = request.form.get("device_id", "").strip()
    if not device_id or device_id.lower() == "unknown":
        device_id = "esp32_01"
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
def enroll_voice():
    """
    Enroll owner's voice. Upload 10-30s clear WAV of owner speaking.
    Form fields: file=<wav>, device_id=<id>
    """
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    file      = request.files["file"]
    device_id = request.form.get("device_id", "unknown").strip()
    filename  = secure_filename(file.filename)
    save_path = os.path.join(ENROLL_FOLDER, filename)
    file.save(save_path)

    wav_path  = convert_to_wav(save_path)
    embedding = get_voice_embedding(wav_path)

    if embedding is None:
        return jsonify({"error": "Could not extract voice embedding"}), 500

    db_save_voice_profile(device_id, embedding)
    print(f"[VoiceID] ✅ Voice enrolled for device={device_id} ({embedding.shape[0]}-dim)")
    return jsonify({
        "message":       f"Voice enrolled for {device_id}",
        "embedding_dim": int(embedding.shape[0]),
        "method":        "mfcc_cosine",
    }), 200

@app.route("/voice/test", methods=["POST"])
def test_voice():
    """Test speaker identification on an audio file without running full pipeline."""
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    file      = request.files["file"]
    device_id = request.form.get("device_id", "unknown").strip()
    filename  = secure_filename(file.filename)
    save_path = os.path.join(AUDIO_FOLDER, "test_" + filename)
    file.save(save_path)
    wav_path = convert_to_wav(save_path)
    result   = identify_speaker(wav_path, device_id)
    return jsonify(result), 200

@app.route("/sally/ask", methods=["POST"])
@require_auth
def ask_sally():
    data      = request.get_json()
    question  = data.get("question","").strip()
    device_id = data.get("device_id","").strip()
    history   = data.get("history", [])  # list of {role, content}
    if not device_id or device_id.lower() == "unknown":
        device_id = "esp32_01"
    if not question:
        return jsonify({"error": "No question"}), 400
    answer = answer_sally_query(question, device_id, None, "", history=history)
    return jsonify({"question": question, "answer": answer, "device_id": device_id}), 200

@app.route("/sally/history", methods=["GET"])
@require_auth
def sally_history():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                if device_id:
                    cur.execute("SELECT id,question,answer,device_id,created_at FROM sally_queries WHERE device_id=%s ORDER BY created_at DESC LIMIT 50;", (device_id,))
                else:
                    cur.execute("SELECT id,question,answer,device_id,created_at FROM sally_queries ORDER BY created_at DESC LIMIT 50;")
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"question":r[1],"answer":r[2],"device_id":r[3],"created_at":str(r[4])} for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/recordings", methods=["GET"])
@require_auth
def list_recordings():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = "SELECT r.id,r.audio_file,r.status,r.created_at,r.device_id,t.text,s.summary FROM recordings r LEFT JOIN transcripts t ON t.recording_id=r.id LEFT JOIN summaries s ON s.recording_id=r.id"
                params = []
                if device_id:
                    q += " WHERE r.device_id=%s"; params.append(device_id)
                q += " ORDER BY r.created_at DESC LIMIT 50;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"audio_file":r[1],"status":r[2],"created_at":str(r[3]),"device_id":r[4],"transcript_path":r[5],"summary_path":r[6]} for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/intents", methods=["GET"])
@require_auth
def get_intents():
    try:
        device_id   = request.args.get("device_id")
        intent_type = request.args.get("type")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = "SELECT id,recording_id,task,intent_type,temporal_cue,fused_confidence,decision,status,scheduled_time,device_id,created_at FROM intents WHERE 1=1"
                params = []
                if device_id:   q += " AND device_id=%s";   params.append(device_id)
                if intent_type: q += " AND intent_type=%s"; params.append(intent_type)
                q += " ORDER BY created_at DESC LIMIT 100;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"recording_id":r[1],"task":r[2],"intent_type":r[3],"temporal_cue":r[4],"fused_confidence":r[5],"decision":r[6],"status":r[7],"scheduled_time":str(r[8]) if r[8] else None,"device_id":r[9],"created_at":str(r[10])} for r in rows]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/reminders/pending", methods=["GET"])
@require_auth
def get_pending_reminders():
    try:
        device_id = request.args.get("device_id")
        with get_db() as conn:
            with conn.cursor() as cur:
                q = "SELECT id,recording_id,task,intent_type,temporal_cue,fused_confidence,decision,scheduled_time,device_id,created_at FROM intents WHERE reminder_sent=FALSE AND status='pending' AND decision IN ('act','confirm') AND (scheduled_time IS NULL OR scheduled_time<=NOW())"
                params = []
                if device_id: q += " AND device_id=%s"; params.append(device_id)
                q += " ORDER BY created_at ASC;"
                cur.execute(q, params)
                rows = cur.fetchall()
        return jsonify([{"id":r[0],"recording_id":r[1],"task":r[2],"intent_type":r[3],"temporal_cue":r[4],"fused_confidence":r[5],"decision":r[6],"scheduled_time":str(r[7]) if r[7] else None,"device_id":r[8],"created_at":str(r[9])} for r in rows]), 200
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

@app.route("/memory/search", methods=["POST"])
@require_auth
def search_memory():
    data      = request.get_json()
    query     = data.get("query","").strip()
    device_id = data.get("device_id","unknown")
    if not query:
        return jsonify({"error": "No query"}), 400
    results = retrieve_context(query, device_id)
    return jsonify([{"content":r[0],"recorded_at":str(r[1]),"similarity":round(float(r[2]),3)} for r in results]), 200

@app.route("/decrypt/transcript/<int:recording_id>", methods=["GET"])
@require_auth
def get_transcript(recording_id):
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT text FROM transcripts WHERE recording_id=%s;", (recording_id,))
                row = cur.fetchone()
        if not row or not row[0]: return jsonify({"error":"Not found"}), 404
        if not os.path.exists(row[0]): return jsonify({"error":"File not on disk"}), 404
        return jsonify({"recording_id": recording_id, "transcript": decrypt_file(row[0]).decode()}), 200
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
        if not row or not row[0]: return jsonify({"error":"Not found"}), 404
        if not os.path.exists(row[0]): return jsonify({"error":"File not on disk"}), 404
        return jsonify({"recording_id": recording_id, "summary": json.loads(decrypt_file(row[0]).decode())}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ── hourly / daily summary endpoints ─────────────────────────────────────────

def generate_hourly_summary(transcripts: list, intents: list,
                             sally_qa: list, device_id: str,
                             date: str, hour: int) -> dict:
    """
    Aggregate multiple transcript texts from one hour into a single
    LLM-generated summary. Result is cached in the hourly_summaries table.
    """
    if not transcripts:
        return {
            "headline":         "No activity",
            "summary":          "No recordings in this period.",
            "topics":           [],
            "mood":             "unknown",
            "action_items":     [],
            "people_mentioned": [],
            "notable_quotes":   [],
        }

    combined = "\n\n---\n\n".join(transcripts)

    prompt = f"""You are summarising a person's recordings from {date} between {hour}:00 and {hour+1}:00.

Summarise ONLY what was said — do not invent or embellish.
Respond ONLY in valid JSON:
{{
  "headline":         "one sentence — what was the main thing happening this hour",
  "summary":          "2-4 sentence paragraph covering the full hour",
  "topics":           ["list","of","topics","discussed"],
  "mood":             "one word describing overall mood/energy",
  "action_items":     ["explicit things the person said they need to do"],
  "people_mentioned": ["names of people mentioned"],
  "notable_quotes":   ["1-3 interesting or important direct quotes"]
}}

Combined transcripts:
{combined[:4000]}
"""
    try:
        completion = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
        )
        return json.loads(completion.choices[0].message.content)
    except Exception as e:
        print(f"[HourlySummary] LLM error: {e}")
        return {
            "headline":         "Summary unavailable",
            "summary":          "",
            "topics":           [],
            "mood":             "unknown",
            "action_items":     [],
            "people_mentioned": [],
            "notable_quotes":   [],
        }

def db_get_hourly_cache(device_id: str, date: str, hour: int):
    """Return cached hourly summary if it exists."""
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT summary_json FROM hourly_summaries
                WHERE device_id=%s AND summary_date=%s AND summary_hour=%s
                LIMIT 1;
            """, (device_id, date, hour))
            row = cur.fetchone()
    return json.loads(row[0]) if row else None

def db_save_hourly_cache(device_id: str, date: str, hour: int, data: dict):
    """Cache an hourly summary so it's not regenerated on every request."""
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO hourly_summaries (device_id, summary_date, summary_hour, summary_json)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (device_id, summary_date, summary_hour)
                DO UPDATE SET summary_json=%s, updated_at=NOW();
            """, (device_id, date, hour, json.dumps(data), json.dumps(data)))

@app.route("/summary/available", methods=["GET"])
@require_auth
def summary_available():
    """
    Return which dates and hours have recordings for a device.
    App uses this to populate the date/hour picker.

    Query params:
      device_id  — required
      date       — optional (YYYY-MM-DD), if omitted returns all dates
    """
    try:
        device_id = request.args.get("device_id", "").strip()
        date      = request.args.get("date", "").strip()
        if not device_id:
            return jsonify({"error": "device_id required"}), 400

        with get_db() as conn:
            with conn.cursor() as cur:
                if date:
                    cur.execute("""
                        SELECT
                            DATE(created_at)                          AS day,
                            EXTRACT(HOUR FROM created_at)::int        AS hour,
                            COUNT(*)                                  AS recording_count,
                            SUM(CASE WHEN status NOT IN
                                ('uploaded','no_speech','tv_audio','error')
                                THEN 1 ELSE 0 END)                    AS processed_count
                        FROM recordings
                        WHERE device_id=%s AND DATE(created_at)=%s
                        GROUP BY day, hour
                        ORDER BY hour ASC;
                    """, (device_id, date))
                else:
                    cur.execute("""
                        SELECT
                            DATE(created_at)                          AS day,
                            EXTRACT(HOUR FROM created_at)::int        AS hour,
                            COUNT(*)                                  AS recording_count,
                            SUM(CASE WHEN status NOT IN
                                ('uploaded','no_speech','tv_audio','error')
                                THEN 1 ELSE 0 END)                    AS processed_count
                        FROM recordings
                        WHERE device_id=%s
                        GROUP BY day, hour
                        ORDER BY day DESC, hour ASC;
                    """, (device_id,))
                rows = cur.fetchall()

        return jsonify([
            {
                "date":            str(r[0]),
                "hour":            r[1],
                "hour_label":      f"{r[1]:02d}:00 – {r[1]+1:02d}:00",
                "recording_count": r[2],
                "processed_count": r[3],
            }
            for r in rows
        ]), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/summary/hourly", methods=["GET"])
@require_auth
def summary_hourly():
    """
    Return aggregated summary + intents + Sally Q&A for one hour.
    Result is cached — first call generates it, subsequent calls return cache.

    Query params:
      device_id  — required
      date       — required (YYYY-MM-DD)
      hour       — required (0-23)
      refresh    — optional, set to 'true' to force regeneration
    """
    try:
        device_id = request.args.get("device_id", "").strip()
        date      = request.args.get("date", "").strip()
        hour_str  = request.args.get("hour", "").strip()
        refresh   = request.args.get("refresh", "false").lower() == "true"

        if not device_id or not date or not hour_str:
            return jsonify({"error": "device_id, date and hour are required"}), 400

        hour = int(hour_str)

        # Return cache unless refresh requested
        if not refresh:
            cached = db_get_hourly_cache(device_id, date, hour)
            if cached:
                print(f"[HourlySummary] Cache hit for {device_id} {date} {hour:02d}:00")
                return jsonify(cached), 200

        print(f"[HourlySummary] Generating for {device_id} {date} {hour:02d}:00...")

        # Fetch all recordings in this hour
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT r.id, r.status, r.created_at, t.text AS transcript_path
                    FROM recordings r
                    LEFT JOIN transcripts t ON t.recording_id = r.id
                    WHERE r.device_id = %s
                      AND DATE(r.created_at) = %s
                      AND EXTRACT(HOUR FROM r.created_at) = %s
                    ORDER BY r.created_at ASC;
                """, (device_id, date, hour))
                recordings = cur.fetchall()

                # Fetch intents from this hour
                cur.execute("""
                    SELECT id, task, intent_type, temporal_cue,
                           fused_confidence, decision, status, scheduled_time, created_at
                    FROM intents
                    WHERE device_id = %s
                      AND DATE(created_at) = %s
                      AND EXTRACT(HOUR FROM created_at) = %s
                    ORDER BY created_at ASC;
                """, (device_id, date, hour))
                intent_rows = cur.fetchall()

                # Fetch Sally Q&A from this hour
                cur.execute("""
                    SELECT id, question, answer, created_at
                    FROM sally_queries
                    WHERE device_id = %s
                      AND DATE(created_at) = %s
                      AND EXTRACT(HOUR FROM created_at) = %s
                    ORDER BY created_at ASC;
                """, (device_id, date, hour))
                sally_rows = cur.fetchall()

        # Decrypt transcripts
        transcripts = []
        recording_ids = []
        for rec in recordings:
            rec_id, status, created_at, transcript_path = rec
            recording_ids.append(rec_id)
            if transcript_path and os.path.exists(transcript_path):
                try:
                    text = decrypt_file(transcript_path).decode("utf-8")
                    transcripts.append(text)
                except Exception:
                    pass

        # Format intents for response
        intents = [
            {
                "id":              row[0],
                "task":            row[1],
                "intent_type":     row[2],
                "temporal_cue":    row[3],
                "fused_confidence": float(row[4]) if row[4] else 0,
                "decision":        row[5],
                "status":          row[6],
                "scheduled_time":  str(row[7]) if row[7] else None,
                "created_at":      str(row[8]),
            }
            for row in intent_rows
        ]

        # Format Sally Q&A
        sally_qa = [
            {
                "id":         row[0],
                "question":   row[1],
                "answer":     row[2],
                "created_at": str(row[3]),
            }
            for row in sally_rows
        ]

        # Generate LLM summary
        llm_summary = generate_hourly_summary(
            transcripts, intents, sally_qa, device_id, date, hour
        )

        # Build full response
        result = {
            "device_id":        device_id,
            "date":             date,
            "hour":             hour,
            "hour_label":       f"{hour:02d}:00 – {hour+1:02d}:00",
            "recording_count":  len(recordings),
            "transcript_count": len(transcripts),
            "generated_at":     datetime.now().isoformat(),
            "summary":          llm_summary,
            "intents":          intents,
            "sally_qa":         sally_qa,
        }

        # Cache for future requests
        db_save_hourly_cache(device_id, date, hour, result)

        return jsonify(result), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/summary/daily", methods=["GET"])
@require_auth
def summary_daily():
    """
    Return a full day overview with per-hour breakdown.
    Shows which hours have activity and key stats for each.
    Does NOT generate LLM summaries for each hour (use /summary/hourly for that).

    Query params:
      device_id  — required
      date       — required (YYYY-MM-DD)
    """
    try:
        device_id = request.args.get("device_id", "").strip()
        date      = request.args.get("date", "").strip()
        if not device_id or not date:
            return jsonify({"error": "device_id and date are required"}), 400

        with get_db() as conn:
            with conn.cursor() as cur:
                # Per-hour stats
                cur.execute("""
                    SELECT
                        EXTRACT(HOUR FROM r.created_at)::int AS hour,
                        COUNT(r.id)                          AS recordings,
                        COUNT(t.id)                          AS transcripts,
                        COUNT(i.id)                          AS intents,
                        COUNT(sq.id)                         AS sally_queries
                    FROM recordings r
                    LEFT JOIN transcripts  t  ON t.recording_id  = r.id
                    LEFT JOIN intents      i  ON i.recording_id  = r.id
                    LEFT JOIN sally_queries sq ON sq.recording_id = r.id
                    WHERE r.device_id = %s AND DATE(r.created_at) = %s
                    GROUP BY hour
                    ORDER BY hour ASC;
                """, (device_id, date))
                hour_rows = cur.fetchall()

                # Day totals
                cur.execute("""
                    SELECT COUNT(DISTINCT r.id), COUNT(DISTINCT i.id), COUNT(DISTINCT sq.id)
                    FROM recordings r
                    LEFT JOIN intents i ON i.recording_id = r.id
                    LEFT JOIN sally_queries sq ON sq.recording_id = r.id
                    WHERE r.device_id = %s AND DATE(r.created_at) = %s;
                """, (device_id, date))
                totals = cur.fetchone()

                # High confidence intents for the day
                cur.execute("""
                    SELECT id, task, intent_type, temporal_cue,
                           fused_confidence, decision, status, scheduled_time, created_at
                    FROM intents
                    WHERE device_id = %s
                      AND DATE(created_at) = %s
                      AND decision = 'act'
                    ORDER BY fused_confidence DESC;
                """, (device_id, date))
                flagged_intents = cur.fetchall()

        hours = [
            {
                "hour":          row[0],
                "hour_label":    f"{row[0]:02d}:00 – {row[0]+1:02d}:00",
                "recordings":    row[1],
                "transcripts":   row[2],
                "intents":       row[3],
                "sally_queries": row[4],
                "has_summary":   db_get_hourly_cache(device_id, date, row[0]) is not None,
            }
            for row in hour_rows
        ]

        return jsonify({
            "device_id":   device_id,
            "date":        date,
            "totals": {
                "recordings":    totals[0] if totals else 0,
                "intents":       totals[1] if totals else 0,
                "sally_queries": totals[2] if totals else 0,
            },
            "hours":  hours,
            "flagged_intents": [
                {
                    "id":              row[0],
                    "task":            row[1],
                    "intent_type":     row[2],
                    "temporal_cue":    row[3],
                    "fused_confidence": float(row[4]) if row[4] else 0,
                    "decision":        row[5],
                    "status":          row[6],
                    "scheduled_time":  str(row[7]) if row[7] else None,
                    "created_at":      str(row[8]),
                }
                for row in flagged_intents
            ],
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/intents/<int:intent_id>/status", methods=["PATCH"])
@require_auth
def update_intent_status(intent_id):
    """
    Update intent status from the app.
    Body: {"status": "completed"} | {"status": "ignored"} | {"status": "pending"}
    """
    try:
        data   = request.get_json()
        status = data.get("status", "").strip()
        if status not in ("completed", "ignored", "pending"):
            return jsonify({"error": "status must be completed, ignored or pending"}), 400
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE intents SET status=%s WHERE id=%s;",
                    (status, intent_id)
                )
        return jsonify({"message": f"Intent {intent_id} status set to {status}"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── admin: token management ───────────────────────────────────────────────────

@app.route("/admin/tokens", methods=["POST"])
def create_token():
    """
    Create an API bearer token. Only callable from localhost.
    Body: {"device_id": "dashboard", "label": "flutter_app"}
    Returns the raw token ONCE — it is not stored in plaintext.
    """
    if request.remote_addr not in ("127.0.0.1", "::1"):
        return jsonify({"error": "Localhost only"}), 403
    data      = request.get_json(silent=True) or {}
    device_id = str(data.get("device_id", "dashboard")).strip()[:100]
    label     = str(data.get("label", "")).strip()[:200]
    raw_token = secrets.token_urlsafe(32)
    token_hash = _hash_token(raw_token)
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO api_tokens (device_id, token_hash, label) VALUES (%s,%s,%s);",
                    (device_id, token_hash, label),
                )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500
    return jsonify({
        "token":   raw_token,
        "label":   label,
        "note":    "Save this token — it will not be shown again.",
    }), 201


# ── window summary (6h rolling or whole-day) ──────────────────────────────────

@app.route("/summary/window", methods=["GET"])
@require_auth
def summary_window():
    """
    Return an aggregated LLM summary for a time window.

    Query params:
      device_id  — required
      window     — required: "6h" | "day" | "24h"
      until      — optional ISO8601 UTC end time (default: now)
      refresh    — optional "true" to bypass cache and regenerate
    """
    try:
        device_id   = request.args.get("device_id", "").strip()
        window_type = request.args.get("window", "").strip()
        until_str   = request.args.get("until", "").strip()
        refresh     = request.args.get("refresh", "false").lower() == "true"

        if not device_id:
            return jsonify({"error": "device_id required"}), 400
        if window_type not in ("6h", "day", "24h"):
            return jsonify({"error": "window must be 6h, day, or 24h"}), 400

        if until_str:
            until = datetime.fromisoformat(until_str.replace("Z", ""))
        else:
            until = datetime.utcnow()

        if window_type == "6h":
            window_start = until - timedelta(hours=6)
        elif window_type == "24h":
            window_start = until - timedelta(hours=24)
        else:  # day — since midnight UTC
            window_start = until.replace(hour=0, minute=0, second=0, microsecond=0)

        # Check idempotency cache
        if not refresh:
            with get_db() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT summary_json FROM window_summaries
                        WHERE device_id=%s AND window_type=%s AND window_start=%s
                        LIMIT 1;
                    """, (device_id, window_type, window_start))
                    row = cur.fetchone()
            if row:
                print(f"[WindowSummary] Cache hit — {device_id} {window_type}")
                return jsonify(row[0]), 200

        print(f"[WindowSummary] Generating {window_type} for {device_id}...")

        # Fetch plaintext chunks from memory_chunks (no decryption needed)
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT mc.content, mc.created_at, mc.recording_id
                    FROM memory_chunks mc
                    WHERE mc.device_id = %s
                      AND mc.created_at >= %s AND mc.created_at <= %s
                    ORDER BY mc.created_at ASC;
                """, (device_id, window_start, until))
                chunk_rows = cur.fetchall()

                cur.execute("""
                    SELECT id, task, intent_type, temporal_cue,
                           fused_confidence, decision, status, scheduled_time, created_at
                    FROM intents
                    WHERE device_id = %s AND created_at >= %s AND created_at <= %s
                    ORDER BY fused_confidence DESC NULLS LAST;
                """, (device_id, window_start, until))
                intent_rows = cur.fetchall()

        # Context size management — newest chunks first for priority truncation
        MAX_CHARS = 14000
        chunks_desc = sorted(chunk_rows, key=lambda c: c[1], reverse=True)
        combined_parts, total_chars, recording_ids = [], 0, set()
        for content, ts, rid in chunks_desc:
            if total_chars + len(content) > MAX_CHARS:
                remaining = MAX_CHARS - total_chars
                if remaining > 100:
                    combined_parts.append(f"[{str(ts)[:16]}] {content[:remaining]}...")
                break
            combined_parts.append(f"[{str(ts)[:16]}] {content}")
            total_chars += len(content)
            recording_ids.add(rid)
        # Re-sort chronologically for the prompt
        combined_text = "\n\n---\n\n".join(reversed(combined_parts))

        intents = [{
            "id":               r[0],
            "task":             r[1],
            "intent_type":      r[2],
            "temporal_cue":     r[3],
            "fused_confidence": float(r[4]) if r[4] is not None else 0.0,
            "decision":         r[5],
            "status":           r[6],
            "scheduled_time":   str(r[7]) if r[7] else None,
            "created_at":       str(r[8]),
        } for r in intent_rows]

        intent_context = "\n".join(
            f"- {i['task']} ({i['intent_type']}, conf={i['fused_confidence']:.2f})"
            for i in intents[:10]
        ) or "None detected"

        window_labels = {
            "6h":  "Last 6 hours",
            "day": "Today (since midnight UTC)",
            "24h": "Last 24 hours",
        }

        if not combined_text.strip():
            llm_result = {
                "headline":          "No activity in this window",
                "summary":           "No recordings were processed in this time window.",
                "topics":            [],
                "mood":              "unknown",
                "action_items":      [],
                "people_mentioned":  [],
                "notable_quotes":    [],
                "suggested_reminders": [],
            }
        else:
            prompt = (
                f"You are Sally, a personal wearable AI assistant. Summarise the owner's recorded speech for the time window below.\n"
                f"Address the owner directly using 'you' and 'your' — never say 'the user' or 'the speaker'.\n\n"
                f"Time window: {window_labels[window_type]} "
                f"({window_start.isoformat()} to {until.isoformat()})\n\n"
                f"Rules:\n"
                f"- Summarise ONLY what was actually said. Do not invent or embellish.\n"
                f"- Identify actionable reminders and important events.\n"
                f"- Detect emotional tone and energy level.\n\n"
                f"Detected intents (pre-extracted for context):\n{intent_context}\n\n"
                f'Respond ONLY in valid JSON:\n'
                f'{{"headline":"one sentence","summary":"3-5 sentences",'
                f'"topics":[],"mood":"one word","action_items":[],'
                f'"people_mentioned":[],"notable_quotes":[],'
                f'"suggested_reminders":[{{"title":"","reason":"","suggested_time_offset_hours":2}}]}}\n\n'
                f"Transcripts:\n{combined_text[:12000]}"
            )
            try:
                comp = client.chat.completions.create(
                    model=LLM_MODEL,
                    messages=[{"role": "user", "content": prompt}],
                    response_format={"type": "json_object"},
                )
                llm_result = json.loads(comp.choices[0].message.content)
            except Exception as exc:
                print(f"[WindowSummary] LLM error: {exc}")
                # Fallback — check if a previous cache entry exists
                try:
                    with get_db() as conn:
                        with conn.cursor() as cur:
                            cur.execute("""
                                SELECT summary_json FROM window_summaries
                                WHERE device_id=%s AND window_type=%s
                                ORDER BY window_start DESC LIMIT 1;
                            """, (device_id, window_type))
                            prev = cur.fetchone()
                    if prev:
                        print("[WindowSummary] Returning last cached summary as fallback")
                        return jsonify(prev[0]), 200
                except Exception:
                    pass
                llm_result = {
                    "headline":          "Summary temporarily unavailable",
                    "summary":           str(exc),
                    "topics":            [],
                    "mood":              "unknown",
                    "action_items":      [],
                    "people_mentioned":  [],
                    "notable_quotes":    [],
                    "suggested_reminders": [],
                }

        result = {
            "device_id":        device_id,
            "window_type":      window_type,
            "window_start":     window_start.isoformat() + "Z",
            "window_end":       until.isoformat() + "Z",
            "recording_count":  len(set(r[2] for r in chunk_rows)),
            "transcript_count": len(chunk_rows),
            "summary":          llm_result,
            "intents":          intents,
            "generated_at":     datetime.utcnow().isoformat() + "Z",
        }

        # Idempotent upsert — safe to call multiple times for the same window
        try:
            with get_db() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO window_summaries
                          (device_id, window_type, window_start, window_end,
                           summary_json, recording_ids, intent_ids)
                        VALUES (%s,%s,%s,%s,%s,%s,%s)
                        ON CONFLICT (device_id, window_type, window_start)
                        DO UPDATE SET summary_json=%s, updated_at=NOW();
                    """, (
                        device_id, window_type, window_start, until,
                        json.dumps(result),
                        list(recording_ids),
                        [i["id"] for i in intents],
                        json.dumps(result),
                    ))
        except Exception as exc:
            print(f"[WindowSummary] Cache write error: {exc}")

        return jsonify(result), 200

    except Exception as exc:
        import traceback; traceback.print_exc()
        return jsonify({"error": str(exc)}), 500


# ── reminders CRUD ────────────────────────────────────────────────────────────

@app.route("/reminders", methods=["GET"])
@require_auth
def list_reminders():
    """
    List user-created reminders.
    Query params: device_id (required), status (pending|resolved|snoozed|all, default pending)
    """
    try:
        device_id = request.args.get("device_id", "").strip()
        status    = request.args.get("status", "pending").strip()
        if not device_id:
            return jsonify({"error": "device_id required"}), 400

        q = """
            SELECT id, device_id, intent_id, title, notes,
                   scheduled_time, repeat_rule, status, created_at, updated_at
            FROM reminders
            WHERE device_id = %s
        """
        params = [device_id]
        if status != "all":
            q += " AND status = %s"
            params.append(status)
        q += " ORDER BY COALESCE(scheduled_time, created_at) ASC;"

        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(q, params)
                rows = cur.fetchall()

        return jsonify([{
            "id":             r[0],
            "device_id":      r[1],
            "intent_id":      r[2],
            "title":          r[3],
            "notes":          r[4],
            "scheduled_time": r[5].isoformat() + "Z" if r[5] else None,
            "repeat_rule":    r[6],
            "status":         r[7],
            "created_at":     r[8].isoformat() + "Z",
            "updated_at":     r[9].isoformat() + "Z",
        } for r in rows]), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/reminders", methods=["POST"])
@require_auth
def create_reminder():
    """
    Create a user reminder, optionally linked to an existing intent.
    Body: {device_id, title, notes?, scheduled_time? (ISO8601), intent_id?, repeat_rule?}
    """
    try:
        data = request.get_json(silent=True) or {}

        device_id     = str(data.get("device_id", "")).strip()
        title         = str(data.get("title", "")).strip()
        notes         = str(data.get("notes", "")).strip()
        intent_id     = data.get("intent_id")
        repeat_rule   = str(data.get("repeat_rule", "none")).strip()
        scheduled_str = data.get("scheduled_time")

        if not device_id or not title:
            return jsonify({"error": "device_id and title are required"}), 400
        if len(title) > 500:
            return jsonify({"error": "title must be 500 characters or fewer"}), 400
        if repeat_rule not in ("none", "daily", "weekly", "monthly"):
            repeat_rule = "none"

        scheduled_time = None
        if scheduled_str:
            try:
                scheduled_time = datetime.fromisoformat(
                    str(scheduled_str).replace("Z", "")
                )
            except ValueError:
                return jsonify({"error": "scheduled_time must be ISO8601"}), 400

        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO reminders
                      (device_id, intent_id, title, notes, scheduled_time, repeat_rule)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id, created_at, updated_at;
                """, (device_id, intent_id, title, notes or None,
                      scheduled_time, repeat_rule))
                new_id, created_at, updated_at = cur.fetchone()

        return jsonify({
            "id":             new_id,
            "device_id":      device_id,
            "intent_id":      intent_id,
            "title":          title,
            "notes":          notes or None,
            "scheduled_time": scheduled_str,
            "repeat_rule":    repeat_rule,
            "status":         "pending",
            "created_at":     created_at.isoformat() + "Z",
            "updated_at":     updated_at.isoformat() + "Z",
        }), 201

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/reminders/<int:reminder_id>", methods=["PATCH"])
@require_auth
def update_reminder(reminder_id):
    """
    Update a reminder's title, notes, scheduled_time, status, or repeat_rule.
    Body: {field: value, ...} — only whitelisted fields are accepted.
    """
    try:
        data    = request.get_json(silent=True) or {}
        allowed = {"title", "notes", "scheduled_time", "status", "repeat_rule"}
        updates = {k: v for k, v in data.items() if k in allowed}
        if not updates:
            return jsonify({"error": "No valid fields provided"}), 400

        if "status" in updates and updates["status"] not in ("pending", "resolved", "snoozed"):
            return jsonify({"error": "status must be pending, resolved, or snoozed"}), 400
        if "title" in updates and len(str(updates["title"])) > 500:
            return jsonify({"error": "title must be 500 characters or fewer"}), 400

        set_parts = [f"{k} = %s" for k in updates]
        set_parts.append("updated_at = NOW()")
        set_clause = ", ".join(set_parts)

        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    f"UPDATE reminders SET {set_clause} WHERE id = %s RETURNING id;",
                    list(updates.values()) + [reminder_id],
                )
                if not cur.fetchone():
                    return jsonify({"error": "Reminder not found"}), 404

        return jsonify({"id": reminder_id, "updated": sorted(updates.keys())}), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/reminders/<int:reminder_id>", methods=["DELETE"])
@require_auth
def delete_reminder(reminder_id):
    """Delete a reminder permanently."""
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM reminders WHERE id = %s RETURNING id;",
                    (reminder_id,),
                )
                if not cur.fetchone():
                    return jsonify({"error": "Reminder not found"}), 404
        return jsonify({"message": f"Reminder {reminder_id} deleted"}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


# ── run ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)