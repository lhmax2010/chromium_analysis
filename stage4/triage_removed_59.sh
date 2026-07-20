#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if (($# != 3)); then
  echo "usage: $0 REMOVED_59.tsv CANDIDATE_FULL_DEFINED_CPP.tsv OUT_DIR" >&2
  exit 2
fi

removed=$1
candidate=$2
out=$3

for tool in awk cut sha256sum sort uniq wc; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done
[[ -f $removed ]] || { echo "missing input: $removed" >&2; exit 2; }
[[ -f $candidate ]] || { echo "missing input: $candidate" >&2; exit 2; }
[[ $(wc -l < "$removed") -eq 59 ]] || { echo "removed input is not 59 rows" >&2; exit 2; }
awk -F '\t' 'NF != 2 { bad++ } END { exit bad != 0 }' "$removed" || {
  echo "removed input must have two TSV columns" >&2
  exit 2
}

mkdir -p "$out"
matches="$out/candidate_named_matches.tsv"
exact_old="$out/exact_old_symbols_still_defined.tsv"
triage="$out/removed_59_triage.tsv"

awk -F '\t' 'BEGIN { OFS="\t" }
  $6 ~ /^v8::Isolate::ValidateAndCanonicalizeUnicodeLocaleId\(/ {
    print "VALIDATE_LOCALE",$1,$2,$3,$5,$6
  }
  $6 ~ /^v8::internal::wasm::WasmError::FormatError\(/ {
    print "WASM_FORMAT_ERROR",$1,$2,$3,$5,$6
  }
  $6 ~ /^v8::internal::Isolate::set_icu_object_in_cache\(/ {
    print "SET_ICU_CACHE",$1,$2,$3,$5,$6
  }
  $6 ~ /^v8::internal::compiler::TurboJsonFile::TurboJsonFile\(/ {
    if ($5 ~ /C1E/) key="TURBO_JSON_C1"
    else if ($5 ~ /C2E/) key="TURBO_JSON_C2"
    else next
    print key,$1,$2,$3,$5,$6
  }' "$candidate" | LC_ALL=C sort -u > "$matches"

[[ $(wc -l < "$matches") -eq 5 ]] || {
  echo "candidate named replacement count is not 5" >&2
  exit 2
}

awk -F '\t' 'NR==FNR { old[$1]=1; next }
  ($5 in old) { print }
  ' "$removed" "$candidate" > "$exact_old"
[[ ! -s $exact_old ]] || {
  echo "one or more removed symbols still have an exact candidate definition" >&2
  exit 2
}

awk -F '\t' 'BEGIN { OFS="\t" }
  NR==FNR {
    key=$1
    replacement[key]=$2 OFS $3 OFS $4 OFS $5 OFS $6
    next
  }
  FNR==1 {
    print "baseline_mangled","baseline_demangled","triage_class", \
          "replacement_status","candidate_dso","candidate_bind", \
          "candidate_visibility","candidate_mangled","candidate_demangled", \
          "evidence_rule"
  }
  {
    raw=$1
    dem=$2
    key=""
    klass=""
    status=""
    rule=""

    if (dem ~ /^v8::Isolate::ValidateAndCanonicalizeUnicodeLocaleId/) {
      key="VALIDATE_LOCALE"
      klass="NAMED_ABI_MIGRATION"
      rule="same-qualified-function;abi-cxx11-tag-removed;libcxx-parameter"
    } else if (dem ~ /^v8::internal::wasm::WasmError::FormatError/) {
      key="WASM_FORMAT_ERROR"
      klass="NAMED_ABI_MIGRATION"
      rule="same-qualified-function;abi-cxx11-tag-removed"
    } else if (dem ~ /^v8::internal::Isolate::set_icu_object_in_cache/) {
      key="SET_ICU_CACHE"
      klass="NAMED_ABI_MIGRATION"
      rule="same-qualified-function;libcxx-and-bundled-icu-namespace"
    } else if (dem ~ /^v8::internal::compiler::TurboJsonFile::TurboJsonFile/) {
      key=(raw ~ /C1E/ ? "TURBO_JSON_C1" : "TURBO_JSON_C2")
      klass="NAMED_ABI_MIGRATION"
      rule="same-constructor-variant;ios-openmode-to-unsigned-int-encoding"
    } else if (dem ~ /regex|_AnyMatcher|_Scanner|_Executor/) {
      klass="LIBSTDCXX_REGEX_INTERNAL"
      rule="std-regex-implementation-namespace;no-one-to-one-libcxx-symbol"
    } else if (dem ~ /_Sp_counted|_Sp_make_shared/) {
      klass="LIBSTDCXX_SHARED_PTR_INTERNAL"
      rule="libstdcxx-shared-ptr-control-block;no-one-to-one-libcxx-symbol"
    } else {
      klass="LIBSTDCXX_OTHER_INTERNAL"
      rule="std-or-libstdcxx-implementation-symbol;no-one-to-one-libcxx-symbol"
    }

    if (key != "") {
      status="CANDIDATE_NAMED_REPLACEMENT_FOUND"
      print raw,dem,klass,status,replacement[key],rule
    } else {
      status="IMPLEMENTATION_CHANGED_NO_ONE_TO_ONE_SYMBOL"
      print raw,dem,klass,status,"-","-","-","-","-",rule
    }
  }' "$matches" "$removed" > "$triage"

awk -F '\t' 'NR>1 { n[$3]++ } END {
  print "NAMED_ABI_MIGRATION=" n["NAMED_ABI_MIGRATION"]+0
  print "LIBSTDCXX_REGEX_INTERNAL=" n["LIBSTDCXX_REGEX_INTERNAL"]+0
  print "LIBSTDCXX_SHARED_PTR_INTERNAL=" n["LIBSTDCXX_SHARED_PTR_INTERNAL"]+0
  print "LIBSTDCXX_OTHER_INTERNAL=" n["LIBSTDCXX_OTHER_INTERNAL"]+0
}' "$triage" > "$out/triage_counts.txt"

grep -qx 'NAMED_ABI_MIGRATION=5' "$out/triage_counts.txt"
grep -qx 'LIBSTDCXX_REGEX_INTERNAL=17' "$out/triage_counts.txt"
grep -qx 'LIBSTDCXX_SHARED_PTR_INTERNAL=27' "$out/triage_counts.txt"
grep -qx 'LIBSTDCXX_OTHER_INTERNAL=10' "$out/triage_counts.txt"
[[ $(($(wc -l < "$triage") - 1)) -eq 59 ]]

sha256sum "$removed" "$candidate" "$triage" > "$out/triage_sha256.txt"
echo "[TRIAGE-OK] rows=59 named=5 regex=17 shared_ptr=27 other=10"
