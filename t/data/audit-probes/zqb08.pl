our $x=1; sub g { local $x=9; $_[0]=3; $x } for my $v ($x) { print g($v) } print "$x\n";
