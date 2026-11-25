my $x=1; sub id { $_[0] } my $y=id($x); $y++; print "$x$y\n";
