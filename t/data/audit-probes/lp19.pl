my @a = (1,2,3); for my $i (0..$#a) { push @a, 9 if $i == 0 } print scalar(@a), "\n";
