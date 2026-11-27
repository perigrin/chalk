my @a=(1,2,3); my @r; for (@a) { push @r, \$_ } ${$r[2]}++; print "@a\n";
