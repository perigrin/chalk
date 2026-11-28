my $n = {v=>1}; my $p = $n; for (2..4) { $p->{next} = {v=>$_}; $p = $p->{next} } my $s = ""; for ($p = $n; $p; $p = $p->{next}) { $s .= $p->{v} } print "$s\n";
