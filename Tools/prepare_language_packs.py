#!/usr/bin/env python3
"""Build indexed, read-only lexical packs from pinned WikDict SQLite exports.

Data and derived databases: CC BY-SA 4.0. No translations are invented.
Usage: python3 Tools/prepare_language_packs.py --source /path/to/downloads
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import unicodedata

VERSION = "wikdict-2026-06-lf1"
SOURCE = "https://download.wikdict.com/dictionaries/sqlite/2_2026-06/"
LICENSE = "https://creativecommons.org/licenses/by-sa/4.0/"
ROOT = Path(__file__).resolve().parent.parent

def normalized(text):
    return unicodedata.normalize("NFC", text.strip())

def build(source, output, code, name):
    input_path = source / f"en-{code}.sqlite3"
    digest = hashlib.sha256(input_path.read_bytes()).hexdigest()
    upstream = sqlite3.connect(f"file:{input_path}?mode=ro", uri=True)
    assert upstream.execute("pragma integrity_check").fetchone()[0] == "ok"
    output.mkdir(parents=True, exist_ok=True)
    path = output / f"en-{code}.sqlite"
    path.unlink(missing_ok=True)
    db = sqlite3.connect(path)
    db.execute("create table entry(lemma text not null, pos text not null, senseID text not null, definition text not null, translations text not null, score real not null, provenance text not null, unique(lemma,pos,senseID,translations))")
    counts = {}
    for lexentry, sense_num, sense, written, trans, score, good, importance in upstream.execute("select * from translation order by written_rep,lexentry,sense,trans_list"):
        if not good or not written or not trans:
            continue
        match = re.search(r"__(\w+)__", lexentry)
        if not match:
            continue
        lemma, pos = normalized(written).lower(), match[1].lower()
        alternatives = list(dict.fromkeys(normalized(t) for t in trans.split(" | ") if t.strip()))
        # Reject annotations, dictionary templates, malformed text and unusually long entries.
        alternatives = [t for t in alternatives if len(t) <= 100 and not any(c in t for c in "{}[]<>\n")]
        if not alternatives or len(lemma) > 80 or not any(c.isalpha() for c in lemma):
            continue
        definition = normalized(sense or "")
        sense_id = lexentry + "#" + hashlib.sha256(definition.encode()).hexdigest()[:12]
        provenance = json.dumps({"source": "WikDict / Wiktionary via DBnary", "url": SOURCE + input_path.name,
                                 "license": "CC-BY-SA-4.0", "sourceSHA256": digest, "lexentry": lexentry,
                                 "wiktionary": "https://en.wiktionary.org/wiki/" + lemma.replace(" ", "_")}, ensure_ascii=False)
        db.execute("insert or ignore into entry values(?,?,?,?,?,?,?)", (lemma,pos,sense_id,definition,json.dumps(alternatives,ensure_ascii=False),float(score or 0),provenance))
    db.execute("create index entry_lookup on entry(lemma,pos)")
    db.commit()
    for pos, count in db.execute("select pos,count(*) from entry group by pos"):
        counts[pos] = count
    lemmas = db.execute("select count(distinct lemma) from entry").fetchone()[0]
    db.execute("vacuum")
    db.close()
    metadata = {"id": f"en-{code}", "languageCode": code, "displayName": name, "version": VERSION,
        "schemaVersion": 1, "lexiconDatabaseName": path.name,
        "supportedFeatures": ["sense-glosses", "part-of-speech", "multiword-entries", "source-provenance", "indexed-lookup"],
        "licenseMetadata": {"license": "CC-BY-SA-4.0", "licenseURL": LICENSE,
            "attribution": "WikDict by Karl Bartel. Wiktionary contributors, extracted via DBnary.",
            "sourceURL": SOURCE + input_path.name, "sourceSHA256": digest,
            "changes": "Normalized NFC, filtered malformed entries, split translation lists, indexed and repackaged by LinguaFranca. Derived data remains CC BY-SA 4.0.",
            "databaseSHA256": hashlib.sha256(path.read_bytes()).hexdigest()}}
    (output / f"en-{code}.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n")
    return {"language": code, "entries": sum(counts.values()), "lemmas": lemmas, "byPOS": counts, "bytes": path.stat().st_size, "sourceSHA256":digest}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT/"Resources"/"LanguagePacks")
    args = parser.parse_args()
    report = [build(args.source,args.output,"de","German"),build(args.source,args.output,"ru","Russian")]
    (args.output/"coverage.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))
