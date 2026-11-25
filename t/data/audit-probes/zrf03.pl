my @a=(1,2); my @r=\(@a); ${$r[1]}=5; print "@a\n";
