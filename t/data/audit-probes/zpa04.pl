our $x=1; for my $v ($x) { local $x=9; print $v; } print $x,"\n";
