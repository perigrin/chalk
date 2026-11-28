our $x = 1; my $y = 2; *x = \$y; { local $x = 5; print $y } print "$x$y\n";
