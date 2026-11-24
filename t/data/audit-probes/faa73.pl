my $d={l=>[1]}; my $e={l=>$d->{l}}; push @{$e->{l}},2; my $n=@{$d->{l}}; $e->{l}=[]; my $m=@{$d->{l}}; print "$n$m\n";
