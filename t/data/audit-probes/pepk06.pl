our $x=0; sub p { print $x } for my $i (1..3) { local $x = $i; p() } p(); print "\n";
