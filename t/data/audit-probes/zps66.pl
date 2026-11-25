my @st=(1); my $n=0; while (@st) { my $x=pop @st; $n+=$x; push @st,$x+1,$x+2 if $x<4 } print "$n\n";
