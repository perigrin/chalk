my $t=0; sub add { $t+=$_[0] } for my $i (1..3) { add($i); $t*=2 } print "$t\n";
