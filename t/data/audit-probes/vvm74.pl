our $x = 1; sub set { $x = $_[0] } { local $x = 2; set(5); print $x } print "$x\n";
