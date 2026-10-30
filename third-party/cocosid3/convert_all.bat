@echo off
echo Convert 3 tracks...
perl siddump_convert_v3.pl dump.txt -frame 0 -track 1 > crazycomets_t1.cid
perl siddump_convert_v3.pl dump.txt -frame 0 -track 2 > crazycomets_t2.cid
perl siddump_convert_v3.pl dump.txt -frame 0 -track 3 > crazycomets_t3.cid
echo Done!
