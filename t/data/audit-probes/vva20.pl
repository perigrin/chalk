our @g = (1,2,3); my $r = \@g; { local $r->[0] = 8; print "@g;" } print "@g\n";
