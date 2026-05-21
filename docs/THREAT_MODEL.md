# Threat model and limitations

This work enables recovery-side automation of credential verification through Samsung's original ODE/KeyMaster path.

It does not:

- bypass encryption
- extract disk keys
- defeat KeyMaster
- recover data without the correct credential
- provide GPU/hashcat-style offline cracking
- enable remote attacks

The practical attack surface requires:

- physical access
- a bootable custom recovery environment
- compatible Samsung stock userspace components
- device/build-specific patching
- weak or guessable credentials

Measured attempt speed on the tested device was roughly 0.66-0.70 seconds per candidate. This makes targeted recovery of remembered or weak credentials possible, but broad brute force remains impractical.
