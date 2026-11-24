my $a={v=>[1],n=>1}; my $b={%$a}; $b->{n}=2; push @{$b->{v}},2; print $a->{n}, scalar(@{$a->{v}}), "\n";
