my $d = {l => [1,2]}; my %c = %$d; push @{$c{l}}, 3; print scalar(@{$d->{l}}), "\n";
