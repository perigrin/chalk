my @a = (1,2); my $r = \@a; @a = (3,4); push @$r, 5; print "@a\n";
