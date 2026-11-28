our $x = 1; sub f { for my $i (1..3) { local $x = $i; return $x if $i == 2 } 0 } print f(), "$x\n";
