import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
import uuid


AUDIO = sys.argv[1] if len(sys.argv) > 1 else "/Users/jago/Documents/vedio/06_subforge/Subforge.mp3"
MODEL = "qwen3-asr-flash-filetrans"
BASE_URL = "https://dashscope.aliyuncs.com/api/v1"
API_KEY = os.environ["DASHSCOPE_API_KEY"]
# 一级：正常断句时直接使用。
PRIMARY_BREAKS = set("。！？!?；;，,")
# 二级：平时不主动切，只有一级切出的片段超长时才作为兜底边界。
FALLBACK_BREAKS = set("、：:")
HARD_MAX_LENGTH = int(sys.argv[2]) if len(sys.argv) > 2 else 32
MIN_EFFECTIVE_LENGTH = 3
# 本次实验把这些口头语/语气助词视为“非有效内容字”。
# “好”只有在自身带标点时按语气词处理，避免把“好吃”“好用”中的“好”误删。
FILLER_WORDS = {"嗯", "呃", "额", "哦", "噢", "哎", "唉", "呢", "啊", "呀", "吧", "嘛"}

SWIFT_NL_TOKENIZER = r'''
import Foundation
import NaturalLanguage

struct Token: Codable {
    let start: Int
    let end: Int
    let text: String
}

let input = ProcessInfo.processInfo.environment["SUBFORGE_TOKENIZE_INPUT"]!.data(using: .utf8)!
let texts = try JSONDecoder().decode([String].self, from: input)
var output: [[Token]] = []

for text in texts {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text
    tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)
    var tokens: [Token] = []
    tagger.enumerateTags(
        in: text.startIndex..<text.endIndex,
        unit: .word,
        scheme: .lexicalClass,
        options: [.omitWhitespace, .omitPunctuation, .joinNames]
    ) { _, range in
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        tokens.append(Token(start: start, end: end, text: String(text[range])))
        return true
    }
    output.append(tokens)
}

let data = try JSONEncoder().encode(output)
FileHandle.standardOutput.write(data)
'''


def json_request(url, method="GET", payload=None, headers=None):
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(request, timeout=300) as response:
        return json.loads(response.read().decode())


def upload_to_dashscope() -> str:
    policy_url = BASE_URL + "/uploads?action=getPolicy&model=" + urllib.parse.quote(MODEL)
    policy = json_request(policy_url, headers={"Authorization": "Bearer " + API_KEY})["data"]
    object_name = "subforge-test-" + str(uuid.uuid4()) + "-Subforge.mp3"
    object_key = policy["upload_dir"] + "/" + object_name
    boundary = "----SubForgeTest" + str(uuid.uuid4())
    body = []

    def field(name, value):
        body.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            str(value).encode(),
            b"\r\n",
        ])

    fields = {
        "OSSAccessKeyId": policy["oss_access_key_id"],
        "Signature": policy["signature"],
        "policy": policy["policy"],
        "x-oss-object-acl": policy["x_oss_object_acl"],
        "x-oss-forbid-overwrite": policy["x_oss_forbid_overwrite"],
        "key": object_key,
    }
    for name, value in fields.items():
        field(name, value)
    field("success_action_status", "200")

    with open(AUDIO, "rb") as audio:
        body.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{object_name}"\r\n'.encode(),
            b"Content-Type: audio/mpeg\r\n\r\n",
            audio.read(),
            f"\r\n--{boundary}--\r\n".encode(),
        ])

    request = urllib.request.Request(
        policy["upload_host"],
        data=b"".join(body),
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        if response.status != 200:
            raise RuntimeError("DashScope upload failed: " + str(response.status))
    return "oss://" + object_key


def transcribe():
    file_url = upload_to_dashscope()
    submit = json_request(
        BASE_URL + "/services/audio/asr/transcription",
        method="POST",
        payload={
            "model": MODEL,
            "input": {"file_url": file_url},
            "parameters": {"channel_id": [0], "enable_itn": False, "enable_words": True},
        },
        headers={
            "Authorization": "Bearer " + API_KEY,
            "Content-Type": "application/json",
            "X-DashScope-Async": "enable",
            "X-DashScope-OssResourceResolve": "enable",
        },
    )
    task_id = submit["output"]["task_id"]
    for _ in range(180):
        result = json_request(BASE_URL + "/tasks/" + task_id, headers={"Authorization": "Bearer " + API_KEY})
        output = result["output"]
        if output["task_status"] == "SUCCEEDED":
            return json_request(output["result"]["transcription_url"])
        if output["task_status"] == "FAILED":
            raise RuntimeError(json.dumps(output, ensure_ascii=False))
        time.sleep(2)
    raise TimeoutError(task_id)


def word_text(word):
    text = word.get("text", word.get("word", ""))
    punctuation = word.get("punctuation", "") or ""
    return text if not punctuation or text.endswith(punctuation) else text + punctuation


def strip_punctuation(text):
    return "".join(
        character
        for character in text
        if not character.isspace() and not unicodedata.category(character).startswith("P")
    )


def is_filler_word(word):
    text = strip_punctuation(word.get("text", word.get("word", "")))
    if text in FILLER_WORDS:
        return True
    punctuation = word.get("punctuation", "") or ""
    return text == "好" and bool(punctuation)


def effective_word_length(word):
    if is_filler_word(word):
        return 0
    return len(strip_punctuation(word_text(word)))


def effective_length(words):
    return sum(effective_word_length(word) for word in words)


def tokenizer_ranges(texts):
    environment = os.environ.copy()
    environment["SUBFORGE_TOKENIZE_INPUT"] = json.dumps(texts, ensure_ascii=False)
    completed = subprocess.run(
        ["swift", "-"],
        input=SWIFT_NL_TOKENIZER.encode(),
        env=environment,
        capture_output=True,
        check=True,
        timeout=60,
    )
    return json.loads(completed.stdout.decode())


def ascii_phrase_text(text):
    cleaned = strip_punctuation(text).strip()
    if not cleaned or not any(character.isalnum() and ord(character) < 128 for character in cleaned):
        return False
    return all(
        ord(character) < 128
        and (character.isalnum() or character in "' -_.")
        for character in cleaned
    )


def flatten_atoms(atoms):
    return [word for atom in atoms for word in atom]


def atom_length(atom):
    return effective_length(atom)


def group_word_atoms(words, ranges):
    """Map NaturalLanguage token ranges back onto ASR word timestamps."""
    source_ranges = []
    offset = 0
    for word in words:
        text = word_text(word)
        source_ranges.append((offset, offset + len(text)))
        offset += len(text)

    intervals = []
    for token in ranges:
        overlapping = [
            index
            for index, (start, end) in enumerate(source_ranges)
            if start < token["end"] and end > token["start"]
        ]
        if overlapping:
            intervals.append((overlapping[0], overlapping[-1]))

    atoms = []
    claimed = set()
    for first, last in intervals:
        if any(index in claimed for index in range(first, last + 1)):
            continue
        atoms.append(words[first:last + 1])
        claimed.update(range(first, last + 1))

    for index, word in enumerate(words):
        if index not in claimed:
            atoms.append([word])

    atoms.sort(key=lambda atom: words.index(atom[0]))

    # NLTokenizer 会把英文按单词返回，这里把相邻英文单词重新合并成一个短语。
    merged = []
    for atom in atoms:
        if merged:
            previous = merged[-1]
            previous_text = "".join(word_text(word) for word in previous)
            current_text = "".join(word_text(word) for word in atom)
            if (
                ascii_phrase_text(previous_text)
                and ascii_phrase_text(current_text)
                and previous_text[-1:] not in PRIMARY_BREAKS | FALLBACK_BREAKS
            ):
                merged[-1] = previous + atom
                continue
        merged.append(atom)
    return merged


def make_chunk(words):
    text = "".join(word_text(word) for word in words)
    punctuation = text[-1:] if text else ""
    return {
        "words": words,
        "text": text,
        "start": words[0]["begin_time"],
        "end": words[-1]["end_time"],
        "kind": "punctuation" if punctuation in PRIMARY_BREAKS | FALLBACK_BREAKS else "none",
        "effective_length": effective_length(words),
    }


def split_primary(atoms):
    chunks = []
    current_atoms = []
    for atom in atoms:
        current_atoms.append(atom)
        if word_text(atom[-1])[-1:] in PRIMARY_BREAKS:
            chunks.append((make_chunk(flatten_atoms(current_atoms)), current_atoms))
            current_atoms = []
    if current_atoms:
        chunks.append((make_chunk(flatten_atoms(current_atoms)), current_atoms))
    return chunks


def apply_rules(sentences):
    output = []
    texts = ["".join(word_text(word) for word in sentence.get("words", [])) for sentence in sentences]
    token_ranges = tokenizer_ranges(texts)

    def normalize_chunks(chunks):
        # 短片段只能在当前 ASR segment 内向后合并，不能跨 segment 借正文。
        normalized = []
        pending = None
        for chunk in chunks:
            if pending is not None:
                chunk = make_chunk(pending["words"] + chunk["words"])
                pending = None

            if chunk["effective_length"] < MIN_EFFECTIVE_LENGTH:
                pending = chunk
            else:
                normalized.append(chunk)

        # 当前 segment 末尾没有后续正文时，才退回向前合并。
        if pending is not None:
            if normalized:
                normalized[-1] = make_chunk(normalized[-1]["words"] + pending["words"])
            else:
                normalized.append(pending)
        return normalized

    for sentence_index, sentence in enumerate(sentences):
        sentence_output = []
        atoms = group_word_atoms(sentence.get("words", []), token_ranges[sentence_index])
        # 一级：先按正常断句标点切，但所有切分仍限制在当前 ASR segment 内。
        for primary_chunk, primary_atoms in split_primary(atoms):
            if primary_chunk["effective_length"] <= HARD_MAX_LENGTH:
                sentence_output.append(primary_chunk)
                continue

            # 二级：只有一级片段超长时，才向前寻找顿号/冒号等兜底标点。
            remaining = primary_atoms[:]
            while remaining:
                current_length = 0
                overflow_index = len(remaining)
                for index, atom in enumerate(remaining):
                    next_length = current_length + atom_length(atom)
                    if next_length > HARD_MAX_LENGTH:
                        overflow_index = index
                        break
                    current_length = next_length

                if overflow_index == len(remaining):
                    sentence_output.append(make_chunk(flatten_atoms(remaining)))
                    break

                # 超过上限后，从超出位置向前找最近的二级兜底标点。
                boundary = None
                for index in range(overflow_index - 1, -1, -1):
                    if word_text(remaining[index][-1])[-1:] in FALLBACK_BREAKS:
                        boundary = index + 1
                        break
                if boundary is None:
                    boundary = max(1, overflow_index)

                sentence_output.append(make_chunk(flatten_atoms(remaining[:boundary])))
                remaining = remaining[boundary:]

        output.extend(normalize_chunks(sentence_output))

    return output


def main():
    payload = transcribe()
    sentences = payload["transcripts"][0]["sentences"]
    result = apply_rules(sentences)

    print("========== QWEN ASR 原始 segment ==========")
    for index, sentence in enumerate(sentences, 1):
        print(f"{index:02d}. [{sentence['begin_time'] / 1000:.2f}-{sentence['end_time'] / 1000:.2f}] {sentence['text']}")
    print(f"\nASR segment 数量：{len(sentences)}")
    print(f"规则切分数量：{len(result)}")
    print("\n========== 改进规则切分结果 ==========")
    for index, chunk in enumerate(result, 1):
        print(f"{index:02d}. [{chunk['start'] / 1000:.2f}-{chunk['end'] / 1000:.2f}] {chunk['text']} ({chunk['effective_length']}有效字)")


if __name__ == "__main__":
    main()
