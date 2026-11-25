sub inc { $_[0]++ } my $x=1; inc($x = $x); inc(my $y = $x); print "$x $y\n";
