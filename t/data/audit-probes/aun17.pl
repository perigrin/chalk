my %h=(a=>1); sub w { $_[0]{b}=2; 0 } my @k = (scalar(keys %h), w(\%h), scalar(keys %h)); print "@k\n";
