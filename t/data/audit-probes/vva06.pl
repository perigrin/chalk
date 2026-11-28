our @a = (1,2,3); { local $a[5] = 8; print scalar(@a), ";" } print scalar(@a), "\n";
