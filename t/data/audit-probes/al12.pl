my @a = (1,2,3); my $r = \@a; push @$r, 4; print "@a\n";
