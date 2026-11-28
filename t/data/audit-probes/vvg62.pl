my $n = {v=>1}; $n->{next} = {v=>2}; $n->{next}{next} = {v=>3}; my $s = 0; for (my $p = $n; $p; $p = $p->{next}) { $s += $p->{v} } print "$s\n";
