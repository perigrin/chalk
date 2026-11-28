our $x = 1; my $y = 5; *x = \$y; sub f { $_[0]++ } f($x); print "$x$y\n";
