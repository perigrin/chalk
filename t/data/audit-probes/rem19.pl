my %d=(l=>[1]); my %e=%d; push @{$e{l}},2; $e{x}=1; print scalar(@{$d{l}}), scalar(keys %d), "\n";
