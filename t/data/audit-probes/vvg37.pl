my @a = (1,2,3); my $r = \@a; push @$r, 4; $#{$r} = 1; print "@a\n";
