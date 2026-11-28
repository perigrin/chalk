my @a = (1,2,3); sub f { $a[$_[1]] = 0; $_[0] } my @t; my $i = 0; for my $x (@a) { push @t, f($x, $i++) } print "@t\n";
