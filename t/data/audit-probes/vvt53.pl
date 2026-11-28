my @a = (1,2,3); sub f { $a[$_[1]] = 0; $_[0] } my @t; my $i = 0; while ($i < 3) { push @t, f($a[$i], $i); $i++ } print "@t\n";
