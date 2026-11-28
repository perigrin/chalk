our @g = (1,2,3); my $r = \@g; { local @{$r}[0,1] = (8,9); print "@g;" } print "@g\n";
