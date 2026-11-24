our @st=(1); my $t=0; while (@st) { my $n=pop @st; $t+=$n; push @st,$n+1,$n+1 if $n<3 } print "$t\n";
