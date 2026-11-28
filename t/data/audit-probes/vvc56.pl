package P; our $v = 1; package main; my $y = 2; *P::v = \$y; $P::v = 5; print "$y\n";
