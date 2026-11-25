my %h=(a=>[1]); my %c=map { $_ => [@{$h{$_}}] } keys %h; push @{$h{a}},2; print scalar(@{$c{a}}), "\n";
