my %h=(a=>2,b=>1,c=>3); my @k = sort { $h{$a} <=> $h{$b} } keys %h; print "@k\n";
