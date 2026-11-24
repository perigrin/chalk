my @st=([1,0]); my $t=0; while (my $f=shift @st) { my ($n,$d)=@$f; $t+=$n*$d; push @st,[$n+1,$d+1] if $d<3 } print "$t\n";
