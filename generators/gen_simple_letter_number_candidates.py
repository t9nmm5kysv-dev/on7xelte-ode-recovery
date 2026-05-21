from pathlib import Path
import itertools

outdir = Path("/home/zyxblvxb/Desktop")

# Put likely letters first.
# Add/remove letters you think you used.
likely_letters = list("abcdefghijklmnopqrstuvwxyz")

# Digit blocks: repeated numbers and simple sequences.
digit_blocks = set()

# repeated digits: 0000, 1111, 00000, 111111, etc.
for d in "0123456789":
    for length in range(4, 9):
        digit_blocks.add(d * length)

# simple sequences
digit_blocks.update([
    "1234", "12345", "123456", "1234567", "12345678",
    "0987", "09876", "098765", "0987654",
    "9876", "98765", "987654", "9876543",
    "4321", "54321", "654321",
    "112233", "111222", "121212", "123123",
    "000111", "111000", "222333", "333222",
    "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999", "0000",
])

digit_blocks = sorted(digit_blocks, key=lambda x: (len(x), x))

def letter_forms_one():
    vals = []
    for l in likely_letters:
        vals.extend([l, l.upper()])
    return sorted(set(vals))

def letter_forms_two_same():
    vals = []
    for l in likely_letters:
        vals.extend([
            l * 2,
            l.upper() * 2,
            l + l.upper(),
            l.upper() + l,
        ])
    return sorted(set(vals))

def letter_forms_two_all():
    vals = []
    for a, b in itertools.product(likely_letters, repeat=2):
        vals.append(a + b)
        vals.append((a + b).upper())
        vals.append(a.upper() + b)
        vals.append(a + b.upper())
    return sorted(set(vals))

def make_patterns(letters, digits, include_dot=True):
    cands = set()
    for l in letters:
        for n in digits:
            cands.add(l + n)
            cands.add(n + l)
            if include_dot:
                cands.add(l + "." + n)
                cands.add(n + "." + l)
                cands.add(l + n + ".")
                cands.add(n + l + ".")
    return cands

def write(name, cands):
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
    path = outdir / name
    path.write_text("\n".join(filtered) + "\n")
    print(path, len(filtered))

one = letter_forms_one()
two_same = letter_forms_two_same()
two_all = letter_forms_two_all()

# Tier S1: one letter + repeated/simple number, no dot.
write("passwords_simple_tier_s1_oneletter_nodot.txt", make_patterns(one, digit_blocks, include_dot=False))

# Tier S2: one letter + repeated/simple number, with dot.
write("passwords_simple_tier_s2_oneletter_dot.txt", make_patterns(one, digit_blocks, include_dot=True))

# Tier S3: two same letters, like aa111111 / A.0000 / 7777bb.
write("passwords_simple_tier_s3_twosame.txt", make_patterns(two_same, digit_blocks, include_dot=True))

# Tier S4: all two-letter combos. Broader.
write("passwords_simple_tier_s4_twoletters_all.txt", make_patterns(two_all, digit_blocks, include_dot=True))
