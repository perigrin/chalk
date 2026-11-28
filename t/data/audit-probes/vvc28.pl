our $x = 1; sub wr { $x = 9 } my $y = 7; *x = \$y; wr(); print "$y\n";
