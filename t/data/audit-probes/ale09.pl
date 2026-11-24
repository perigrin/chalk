our $x=1; sub g { $_[0] + 1 } my $t=0; for ($x) { $t = g($_) } print "$t\n";
