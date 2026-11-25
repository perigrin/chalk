my %h=(a=>[1]); my %c=%h; push @{$c{a}}, 2; $c{b}=1; print scalar(@{$h{a}}), scalar(keys %h), "\n";
