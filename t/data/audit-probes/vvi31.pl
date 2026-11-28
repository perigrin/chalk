my $s = "a"; my $t = "b"; ($s, $t) = ("$s$t", "$t$s"); print "$s$t\n";
