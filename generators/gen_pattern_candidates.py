from pathlib import Path
import itertools

out = Path("/home/zyxblvxb/Desktop/passwords_patterned.txt")

# Failed numeric roots / phone fragments.
numbers = [
    "632765",
    "622628",
    "620449",
    "0987",
    "098765",
    "12345",
    "123456",
    "345699",
    "111111",
]

# Word roots. Add/remove based on memory.
words = [
    "yoll",
    "asd",
    "omer",
    "omar",
    "semsi",
    "zyx",
    "zyxblvxb",
]

def variants_word(w):
    vals = {
        w,
        w.lower(),
        w.upper(),
        w[:1].upper() + w[1:].lower(),
    }
    return {x for x in vals if x}

def variants_num(n):
    vals = {n}

    # common chunks
    if len(n) >= 3:
        vals.add(n[:3])
        vals.add(n[-3:])
    if len(n) >= 4:
        vals.add(n[:4])
        vals.add(n[-4:])
    if len(n) >= 5:
        vals.add(n[:5])
        vals.add(n[-5:])

    # reverse
    vals.add(n[::-1])

    return {x for x in vals if x}

word_vars = sorted({v for w in words for v in variants_word(w)})
num_vars = sorted({v for n in numbers for v in variants_num(n)})

cands = set()

# Main likely patterns.
for w in word_vars:
    for n in num_vars:
        cands.add(w + n)
        cands.add(w + "." + n)
        cands.add(w + n + ".")
        cands.add(w + "." + n + ".")
        cands.add(n + w)
        cands.add(n + "." + w)
        cands.add(n + w + ".")
        cands.add(n + "." + w + ".")

# Two numeric chunks around a word.
for w in word_vars:
    for a, b in itertools.permutations(num_vars, 2):
        if len(a) + len(b) > 10:
            continue
        cands.add(a + w + b)
        cands.add(a + "." + w + b)
        cands.add(w + a + "." + b)
        cands.add(w + "." + a + "." + b)

# Dot inserted inside phone fragments + word.
for w in word_vars:
    for n in numbers:
        for i in range(1, len(n)):
            dotted = n[:i] + "." + n[i:]
            cands.add(w + dotted)
            cands.add(w + "." + dotted)
            cands.add(dotted + w)
            cands.add(dotted + "." + w)

# Known failed form mutated from yoll.0987
for w in variants_word("yoll"):
    for n in num_vars:
        cands.add(w + "." + n)
        cands.add(w + n)
        cands.add(w + ".0" + n)
        cands.add(w + ".00" + n)

# Policy filter: at least one letter, only letters/digits/dot.
filtered = []
for c in cands:
    if len(c) < 4:
        continue
    if not any(ch.isalpha() for ch in c):
        continue
    if not all(ch.isalnum() or ch == "." for ch in c):
        continue
    filtered.append(c)

filtered = sorted(set(filtered), key=lambda x: (len(x), x.lower(), x))

out.write_text("\n".join(filtered) + "\n", encoding="utf-8")
print("wrote:", out)
print("candidates:", len(filtered))
