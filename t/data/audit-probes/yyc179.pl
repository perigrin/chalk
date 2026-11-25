my %h=(a=>1); my @b = (scalar(keys %h), $h{b}=1, scalar(keys %h)); print "@b\n";
