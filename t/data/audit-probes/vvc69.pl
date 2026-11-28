our $x = 1; my $y = 5; *x = \$y; my $s = "$x"; $y = 6; $s .= $x; print "$s\n";
