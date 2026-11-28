my @a = (3,1,2); my @i = sort { $a[$a] <=> $a[$b] } 0..$#a; print "@i\n";
