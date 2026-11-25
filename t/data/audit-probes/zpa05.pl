our $x=1; sub g { $x=3 } for my $v ($x) { g(); print $v,"\n"; }
