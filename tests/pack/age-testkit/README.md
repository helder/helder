# age's testkit

age's test vectors from C2SP's CCTV (https://github.com/C2SP/CCTV, `age/testdata`,
commit b88c4b20, CC0): the X25519, header (`hmac_*`, `stanza_*`, `version_*`) and
STREAM vectors, not the scrypt, armor or post-quantum hybrid ones.
`src/helder/pack/age/Age.test.hx` decrypts each one `index.txt` names.
