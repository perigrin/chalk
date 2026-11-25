our $g=1; for my $x ($g) { local $g=5; $x=7 } print "$g\n";
