my @a = (1,2,3); my @b = (4); my $r = \@a; $r = \@b if @a > 2; push @$r, 9; print "@a|@b\n";
