my %h=(k=>1); sub f { $h{k}=9; 1 } my $n = $h{k} + f(); print "$n\n";
