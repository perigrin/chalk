my %h=(a=>[1]); my %c=%h; push @{$h{a}},2; print scalar(@{$c{a}}), "\n";
