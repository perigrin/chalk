my $x=1; sub id { $_[0] } for (id($x)) { $_++ } print "$x\n";
