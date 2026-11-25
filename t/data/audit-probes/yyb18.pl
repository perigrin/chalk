my @a=(1,2); my @r; for my $x (@a) { push @r, \$x } ${$r[0]}=9; print "@a\n";
