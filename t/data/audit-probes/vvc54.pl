our $x = 1; my $y = 2; my $g = \*x; *$g = \$y; $x = 5; print "$y\n";
