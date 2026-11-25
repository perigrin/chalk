sub inc { $_[0]++ } my $x=1; inc($x, $x); inc($x) for 1..3; print "$x\n";
