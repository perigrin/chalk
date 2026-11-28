our @a = (1,2,3); my $r = \@a; { local @a = (3); push @$r, 4; print "@a;" } print "@a\n";
