my %h=(l=>[1]); my @c=($h{l}) x 2; push @{$c[0]},2; print scalar(@{$c[1]}),"\n";
