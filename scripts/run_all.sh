#!/sbin/sh
cd /cache/decrypt_work
SHOW_CANDIDATE=0 MAX_TRIES=999999 PLANNED_TRIES=419152 CHECK_DM_EVERY=250 STATUS_EVERY=100 sh start_local_decrypt.sh passwords_seqrep_all.txt
