our $x = 1; for my $e ($x) { local $x = 2; $e = 9 } print "$x\n";
