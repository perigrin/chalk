my @a = (1,2); my $r = \@a; my @b = @$r; push @$r, 3; print "@a|@b\n";
