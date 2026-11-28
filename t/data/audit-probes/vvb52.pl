my @a = (1,2,3); my @r; for my $e (@a) { push @r, \$e } ${$r[0]} = 9; print "@a\n";
