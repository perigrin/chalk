my $r={a=>[1,2]}; my $c={%$r}; push @{$c->{a}},3; print scalar(@{$r->{a}}),"\n";
