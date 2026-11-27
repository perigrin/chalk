our $x = 1; my $z = 7; *x = \$z; $z++; print "$x\n";
