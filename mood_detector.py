import os
import re
import requests

MODEL_ID = "j-hartmann/emotion-english-distilroberta-base"

HF_API_URL = (
    f"https://router.huggingface.co/hf-inference/models/{MODEL_ID}"
)

mood_mapping = {
    "sadness": "Sad",
    "anger": "Stressed",
    "fear": "Anxious",
    "joy": "Happy",
    "neutral": "Neutral",
    "surprise": "Energised",
    "disgust": "Stressed"
}


def _classify_text(text):
    hf_token = os.getenv("HF_TOKEN")

    if not hf_token:
        raise RuntimeError("HF_TOKEN is not configured")

    headers = {
        "Authorization": f"Bearer {hf_token}",
        "Content-Type": "application/json",
    }

    payload = {
        "inputs": text
    }

    response = requests.post(
        HF_API_URL,
        headers=headers,
        json=payload,
        timeout=60
    )

    if response.status_code != 200:
        raise RuntimeError(
            f"Hugging Face error {response.status_code}: {response.text}"
        )

    result = response.json()

    if not isinstance(result, list) or len(result) == 0:
        raise RuntimeError(
            f"Unexpected Hugging Face response: {result}"
        )

    outputs = result[0]

    if not isinstance(outputs, list):
        outputs = [outputs]

    outputs = sorted(
        outputs,
        key=lambda x: x["score"],
        reverse=True
    )

    return outputs


def detect_mood(text):
    text = text.strip()

    if len(text) < 5:
        return {
            "mood": "Neutral",
            "intensity": 30
        }

    # Get emotion prediction from Hugging Face
    outputs = _classify_text(text)

    primary = outputs[0]

    label = primary["label"].lower()
    score = primary["score"]

    # Convert model emotion into MUMS.ai mood
    if score < 0.4:
        mood = "Neutral"
        intensity = 40
    else:
        mood = mood_mapping.get(label, "Neutral")
        intensity = int(score * 100)

    lower = text.lower()

    # --------------------------------------------------
    # Energetic phrase overrides
    # --------------------------------------------------

    energetic_phrases = [
        "excited",
        "pumped",
        "energetic",
        "hyped",
        "full of energy",
        "let's go",
        "lets go",
        "energised",
        "active",
        "lively",
        "vitality",
        "on top of the world",
        "unstoppable",
        "productive",
        "adrenaline",
        "rushing",
        "pumping",
        "can't sit still",
        "cant sit still"
    ]

    if any(p in lower for p in energetic_phrases):
        mood = "Energised"
        intensity = max(intensity, 80)

    # --------------------------------------------------
    # Sad phrase overrides
    # --------------------------------------------------

    sad_phrases = [
        "breakup",
        "thinking about her",
        "thinking about him",
        "heartbroken",
        "not okay",
        "not ok"
    ]

    if any(p in lower for p in sad_phrases):
        mood = "Sad"
        intensity = max(intensity, 70)

    # --------------------------------------------------
    # Neutral / okay phrase overrides
    # --------------------------------------------------

    ok_phrases = [
        "it's okay",
        "its okay",
        "i'm okay",
        "im okay",
        "am okay",
        "not bad",
        "fine",
        "not great but",
        "not the best but",
        "not terrible",
        "could be worse",
        "not the worst"
    ]

    is_ok = (
        any(p in lower for p in ok_phrases)
        and "not okay" not in lower
        and "not ok" not in lower
    )

    if is_ok:
        mood = "Neutral"
        intensity = min(intensity, 55)

    # --------------------------------------------------
    # Feedback-based mood input
    # Example:
    # "I feel sad with intensity 7"
    # --------------------------------------------------

    fb_match = re.search(
        r'i feel (sad|neutral|better|happy|energised) with intensity (\d+)',
        lower
    )

    if fb_match:
        base_mood = fb_match.group(1)
        val = int(fb_match.group(2)) * 10

        mapping = {
            "sad": "Sad",
            "neutral": "Neutral",
            "better": "Happy",
            "happy": "Happy",
            "energised": "Energised"
        }

        mood = mapping.get(base_mood, "Neutral")
        intensity = val

    # --------------------------------------------------
    # Clamp intensity
    # --------------------------------------------------

    if mood == "Neutral":
        intensity = max(30, min(intensity, 60))
    else:
        intensity = max(30, min(intensity, 90))

    return {
        "mood": mood,
        "intensity": intensity
    }
