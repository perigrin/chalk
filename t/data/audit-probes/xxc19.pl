package P; our ($a,$b); sub srt { sort { $a <=> $b } @_ } package main; print join(",", P::srt(3,1,2)), "\n";
