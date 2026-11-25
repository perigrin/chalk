my %h=(l=>[1,2]); my @b=(@{$h{l}}, $h{l}[0]=9); print "@b\n";
