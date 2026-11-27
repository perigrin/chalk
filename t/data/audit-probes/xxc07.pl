my %h=(a=>2,b=>1,c=>2); my @k = sort { $h{$b} <=> $h{$a} or $a cmp $b } keys %h; print "@k\n";
