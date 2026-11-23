my %h=(a=>1,b=>2,c=>3); my $t=0; for my $k (sort keys %h) { delete $h{c} if $k eq "a"; $t+=$h{$k}//0 } print "$t\n";
