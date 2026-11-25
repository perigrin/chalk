my $h={}; print exists $h->{a}{b} ? 1 : 0, exists $h->{a} ? 1 : 0, scalar(keys %$h), "\n";
