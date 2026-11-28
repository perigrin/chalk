our $x = 1; sub f { *x = \$_[0]; $x++ } my $y = 5; f($y); print "$y\n";
