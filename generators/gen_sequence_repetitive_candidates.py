from pathlib import Path

out1 = Path("/home/zyxblvxb/Desktop/passwords_seqrep_tier1.txt")
out2 = Path("/home/zyxblvxb/Desktop/passwords_seqrep_tier2.txt")
out3 = Path("/home/zyxblvxb/Desktop/passwords_seqrep_tier3.txt")

likely_letters = list("aosdmyzxlqwertyuiopghjkvbnfc")
all_letters = list("abcdefghijklmnopqrstuvwxyz")

anchors_remembered = {
    "11223344",
    "112233",
    "223344",
    "1122",
    "3344",
    "123456",
    "12345",
    "111111",
    "1111",
    "345699",
    "098765",
    "0987",
}

anchors = set(anchors_remembered)

# Ascending sequences 1..9, minimum length 1.
seq = "123456789"
for start in range(len(seq)):
    for end in range(start + 1, len(seq) + 1):
        anchors.add(seq[start:end])

# Descending sequences 9..1.
seq = "987654321"
for start in range(len(seq)):
    for end in range(start + 1, len(seq) + 1):
        anchors.add(seq[start:end])

# 0-prefixed descending-ish common phone keypad style.
seq = "0987654321"
for start in range(len(seq)):
    for end in range(start + 1, len(seq) + 1):
        anchors.add(seq[start:end])

# Repeated digits.
for d in "0123456789":
    for ln in range(1, 10):
        anchors.add(d * ln)

# Pair/repetition patterns.
anchors.update([
    "1212", "121212", "12121212",
    "123123", "123123123",
    "1122", "112233", "11223344", "1122334455",
    "001122", "00112233", "0011223344",
    "223344", "334455", "445566", "556677", "667788", "778899",
    "111222", "222333", "333444", "444555", "555666", "666777", "777888", "888999",
])

# Do not keep pure anchors that are too long or empty.
anchors = {a for a in anchors if 1 <= len(a) <= 10}

def letter_cases_one(l):
    return {l.lower(), l.upper()}

def letter_cases_two_same(l):
    return {l.lower()*2, l.upper()*2, l.upper()+l.lower(), l.lower()+l.upper()}

def valid(x):
    return (
        len(x) >= 4
        and any(ch.isalpha() for ch in x)
        and all(ch.isalnum() or ch == "." for ch in x)
    )

def add_one_letter(cands, n, letters, inside=True, dot=True):
    for l in letters:
        for lf in letter_cases_one(l):
            # prefix/suffix
            cands.add(lf + n)
            cands.add(n + lf)

            if dot:
                cands.add(lf + "." + n)
                cands.add(n + "." + lf)
                cands.add(lf + n + ".")
                cands.add(n + lf + ".")

            # inside insertion
            if inside:
                for i in range(1, len(n)):
                    cands.add(n[:i] + lf + n[i:])
                    if dot:
                        cands.add(n[:i] + "." + lf + n[i:])
                        cands.add(n[:i] + lf + "." + n[i:])
                        cands.add(n[:i] + "." + lf + "." + n[i:])

def add_two_same(cands, n, letters, inside=True, dot=True):
    for l in letters:
        for lf in letter_cases_two_same(l):
            cands.add(lf + n)
            cands.add(n + lf)

            if dot:
                cands.add(lf + "." + n)
                cands.add(n + "." + lf)
                cands.add(lf + n + ".")
                cands.add(n + lf + ".")

            if inside:
                for i in range(1, len(n)):
                    cands.add(n[:i] + lf + n[i:])
                    if dot:
                        cands.add(n[:i] + "." + lf + n[i:])
                        cands.add(n[:i] + lf + "." + n[i:])

def priority_anchor(n):
    # Prefer remembered anchors and clean common sequences first.
    if n in anchors_remembered:
        return 0
    if n in {"1234", "12345", "123456", "1234567", "12345678", "123456789",
             "9876", "98765", "987654", "9876543", "98765432", "987654321",
             "0987", "09876", "098765", "0987654", "09876543"}:
        return 1
    if len(set(n)) == 1:
        return 2
    return 3

def sort_candidates(cands):
    filtered = {x for x in cands if valid(x)}
    return sorted(filtered, key=lambda x: (len(x), x.lower(), x))

tier1 = set()
tier2 = set()
tier3 = set()

# Tier 1: remembered anchors + strongest ordered/repeated anchors, one likely letter.
tier1_anchors = [a for a in anchors if priority_anchor(a) <= 1 and 3 <= len(a) <= 9]
for n in tier1_anchors:
    add_one_letter(tier1, n, likely_letters[:14], inside=True, dot=True)

# Tier 2: all ordered/repeated anchors, one letter all alphabet.
tier2_anchors = [a for a in anchors if 2 <= len(a) <= 9]
for n in tier2_anchors:
    add_one_letter(tier2, n, all_letters, inside=True, dot=True)

# Tier 3: two same letters, likely letters only.
tier3_anchors = [a for a in anchors if 2 <= len(a) <= 9]
for n in tier3_anchors:
    add_two_same(tier3, n, likely_letters[:16], inside=True, dot=True)

tier1 = sort_candidates(tier1)
tier2 = sort_candidates(set(tier2) - set(tier1))
tier3 = sort_candidates(set(tier3) - set(tier1) - set(tier2))

out1.write_text("\n".join(tier1) + "\n")
out2.write_text("\n".join(tier2) + "\n")
out3.write_text("\n".join(tier3) + "\n")

print(out1, len(tier1))
print(out2, len(tier2))
print(out3, len(tier3))
