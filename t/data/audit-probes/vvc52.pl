our $x = 1; my $y = 2; *main::x = \$y; $x = 5; print "$y\n";
