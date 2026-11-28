my %h = (b=>2, a=>1); my ($mk) = sort { $h{$b} <=> $h{$a} } keys %h; print "$mk\n";
