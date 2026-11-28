our $x = 1; for ($x) { local $x = 2; print $_ } print "$x\n";
