our @a = (1,2,3); my $r = \@a; *b = $r; our @b; push @b, 4; print "@a\n";
