my %h=(a=>1); while (my ($k,$v)=each %h) { $h{$k}=$v+1 } print "$h{a}\n";
