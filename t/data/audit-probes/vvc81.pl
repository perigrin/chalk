our $x = 1; my $y = 5; *x = \$y; my ($p, $q) = ($x, $y); $x = 0; print "$p$q$y\n";
