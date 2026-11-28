our $x = 1; sub bnd { *x = \$_[0] } my $y = 7; bnd($y); $x++; print "$x$y\n";
