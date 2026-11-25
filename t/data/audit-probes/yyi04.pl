sub inc { $_[0]++ } my $x=1; inc($x + 0); inc("$x"); inc(-$x); inc("" . $x); print "$x\n";
