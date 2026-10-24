#!/usr/bin/env python3
"""Add attested noun forms to lexical packs; no suffix guesses for target languages.

Build-only dependencies: german-nouns 1.2.5 (CC BY-SA4.0 data),
pymorphy3-dicts-ru 2.4.417150.4580142 (OpenCorpora CC BY-SA3.0 data),
pymorphy3 2.0.6 and dawg2-python 0.9.0 (MIT readers).
The iOS app uses only the resulting indexed SQLite tables, never Python.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys
import unicodedata
import zipfile

def key(word):
    return unicodedata.normalize("NFC",word.replace("\u0301","")).lower()

def open_pack(root, code):
    db = sqlite3.connect(root/f"en-{code}.sqlite")
    db.execute("drop table if exists nounForm")
    db.execute("create table nounForm(lemma text, number text, surface text, gender text, source text, license text, unique(lemma,number,surface,gender))")
    db.execute("drop table if exists caseForm")
    db.execute("create table caseForm(lemma text, number text, grammaticalCase text, surface text, gender text, source text, license text, unique(lemma,number,grammaticalCase,surface,gender))")
    return db

def finish(root, code, db, source, license_name, version, archive):
    db.execute("create index noun_form_lookup on nounForm(lemma,number)")
    db.execute("create index case_form_lookup on caseForm(lemma,number,grammaticalCase)")
    db.commit(); db.execute("vacuum")
    count = db.execute("select count(*) from nounForm").fetchone()[0]
    db.close()
    path = root/f"en-{code}.json"
    manifest = json.loads(path.read_text())
    manifest["version"] = "wikdict-2026-06-lf2"
    manifest["supportedFeatures"] = list(dict.fromkeys(manifest["supportedFeatures"]+["attested-nominative-noun-plurals", "attested-noun-cases"]))
    manifest["licenseMetadata"].update({"morphologySource":source,"morphologyLicense":license_name,
        "morphologyVersion":version,"morphologyArchiveSHA256":hashlib.sha256(archive.read_bytes()).hexdigest(),
        "databaseSHA256":hashlib.sha256((root/f"en-{code}.sqlite").read_bytes()).hexdigest()})
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    return count

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    args = parser.parse_args()
    source,root = args.sources,args.output
    de_wheel = source/"german_nouns-1.2.5-py3-none-any.whl"
    ru_wheel = source/"pymorphy3_dicts_ru-2.4.417150.4580142-py2.py3-none-any.whl"
    de = open_pack(root,"de")
    rows = csv.DictReader(io.StringIO(zipfile.ZipFile(de_wheel).read("german_nouns/nouns.csv").decode()))
    for row in rows:
        if "Substantiv" not in row["pos"] or not row["lemma"].isalpha():continue
        gender = row["genus"]
        for field,form in row.items():
            case = {"nominativ":"nominative", "genitiv":"genitive", "dativ":"dative", "akkusativ":"accusative"}.get(field.split(' ')[0])
            if case and form.isalpha() and '*' not in field:
                number = 'plural' if 'plural' in field else 'singular'
                de.execute("insert or ignore into caseForm values(?,?,?,?,?,?,?)", (key(row['lemma']),number,case,form,gender,"german-nouns/WiktionaryDE","CC-BY-SA-4.0"))
            if field.startswith("nominativ plural") and form.isalpha() and not field.endswith("*"):
                de.execute("insert or ignore into nounForm values(?,?,?,?,?,?)",(key(row["lemma"]),"plural",form,gender,"german-nouns/WiktionaryDE","CC-BY-SA-4.0"))
    de_count = finish(root,"de",de,"https://github.com/gambolputty/german-nouns","CC-BY-SA-4.0","1.2.5",de_wheel)

    sys.path.insert(0,str((source/"python").resolve()))
    import pymorphy3
    analyzer = pymorphy3.MorphAnalyzer()
    ru = open_pack(root,"ru")
    lemmas = set()
    for (translations,) in ru.execute("select translations from entry where pos='noun'"):
        lemmas.update(key(w) for w in json.loads(translations) if key(w).isalpha())
    for lemma in sorted(lemmas):
        for parsed in analyzer.parse(lemma):
            if not parsed.is_known or parsed.tag.POS != "NOUN" or parsed.normal_form != lemma:continue
            for form in parsed.lexeme:
                case = {'nomn':'nominative','gent':'genitive','datv':'dative','accs':'accusative','ablt':'instrumental','loct':'prepositional','loc2':'locative'}.get(form.tag.case)
                if case and form.word.isalpha():
                    ru.execute("insert or ignore into caseForm values(?,?,?,?,?,?,?)", (lemma,'plural' if form.tag.number=='plur' else 'singular',case,form.word,parsed.tag.gender or "","OpenCorpora/pymorphy3-dicts-ru","CC-BY-SA-3.0"))
                if "nomn" in form.tag and "plur" in form.tag:
                    ru.execute("insert or ignore into nounForm values(?,?,?,?,?,?)",(lemma,"plural",form.word,parsed.tag.gender or "","OpenCorpora/pymorphy3-dicts-ru","CC-BY-SA-3.0"))
    ru_count = finish(root,"ru",ru,"https://opencorpora.org/?page=downloads","CC-BY-SA-3.0","2.4.417150.4580142",ru_wheel)
    coverage = json.loads((root/"coverage.json").read_text())
    for record in coverage:
        code=record["language"]
        record["nounForms"] = de_count if code=="de" else ru_count
        record["bytes"] = (root/f"en-{code}.sqlite").stat().st_size
    (root/"coverage.json").write_text(json.dumps(coverage,indent=2)+"\n")
    print(json.dumps({"GermanNounForms":de_count,"RussianNounForms":ru_count}))

if __name__ == "__main__":main()
