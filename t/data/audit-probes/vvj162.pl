my @a = (1,2,3); sub ret { \@a } my $b = ret(); $b->[0] = 9; push @{ret()}, 4; print "@a\n";
