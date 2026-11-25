our $x=1; for my $v ($x) { local $x=9; $v=3; print $x } print "$x\n";
