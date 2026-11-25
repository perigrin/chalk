my $n=0; for my $x (1..3) { redo if $n++==1; } print "$n\n";
