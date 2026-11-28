our @a = (1,2); { my $r = \@a; local @$r = (7); print "@a;" } print "@a\n";
