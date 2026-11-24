my $t=0; my @q=(1,0,2); for my $d (@q) { my $r = eval { 10/$d }; $t += $r // -1 } print "$t\n";
