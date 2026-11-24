my %h=(a=>[1]); my %c=%h; push @{$c{a}},2; $c{b}=1; print scalar(@{$h{a}}), " ", exists $h{b}?1:0, "\n";
