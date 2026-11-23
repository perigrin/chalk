my $n=0; my @st=(1); while (@st) { my $x=pop @st; $n++; push @st,$x+1,$x+2 if $x<3 } print "$n\n";
