my @a = (1,2,3); sub f { $a[$_[1]] = 0; $_[0] } my @t; for my $i (0..2) { push @t, f($a[$i], $i) } print "@t\n";
